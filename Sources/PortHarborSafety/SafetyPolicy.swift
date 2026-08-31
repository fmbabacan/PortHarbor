import Foundation
import Darwin
import PortHarborCore

public enum StopEligibility: Equatable, Sendable {
    case allowed
    case denied(reason: String)
}

public struct SafetyPolicy: Sendable {
    public init() {}

    public func evaluate(service: DiscoveredService) -> StopEligibility {
        guard service.category != .system else {
            return .denied(reason: "System services cannot be stopped by PortHarbor.")
        }

        guard service.process.pid > 1 else {
            return .denied(reason: "The system root process cannot be stopped.")
        }

        guard service.process.startTime != nil else {
            return .denied(reason: "Process identity is incomplete. Refresh discovery before stopping it.")
        }

        if let protected = ([service.process] + service.ancestry).first(where: {
            ProtectedProcessBoundary.isProtected($0)
        }) {
            return .denied(
                reason: "The process tree crosses protected boundary \(protected.name)."
            )
        }

        return .allowed
    }
}

public enum StopSignal: Int32, Codable, Sendable {
    case terminate = 15
    case kill = 9
}

public enum StopAuthorization: Equatable, Sendable {
    case graceful
    case forceKillExplicitlyConfirmed
}

public enum StopTarget: Equatable, Sendable {
    case process(pid: Int32)
    case processGroup(id: Int32)
}

public struct TerminationPlan: Equatable, Sendable {
    public let serviceID: String
    public let expectedIdentity: ProcessIdentity
    public let target: StopTarget
    public let signal: StopSignal
    public let explanation: String

    public init(
        serviceID: String,
        expectedIdentity: ProcessIdentity,
        target: StopTarget,
        signal: StopSignal,
        explanation: String
    ) {
        self.serviceID = serviceID
        self.expectedIdentity = expectedIdentity
        self.target = target
        self.signal = signal
        self.explanation = explanation
    }
}

public enum StopPlanningError: Error, Equatable, Sendable {
    case ineligible(String)
    case forceKillRequiresSeparateAuthorization
    case unsafeProcessGroup
}

public struct ProtectedProcessBoundary: Sendable {
    private static let protectedNames: Set<String> = [
        "launchd", "login", "sshd", "terminal", "iterm2", "warp", "wezterm",
        "zsh", "bash", "fish", "sh", "code", "electron", "xcode",
        "docker", "dockerd", "containerd", "podman", "colima", "orbstack",
        "brew", "homebrew", "launchctl", "systemd", "portharbor"
    ]

    public static func isProtected(_ process: ProcessIdentity) -> Bool {
        let name = process.name.lowercased()
        let executable = process.executablePath?.lowercased() ?? ""

        return protectedNames.contains(name)
            || protectedNames.contains { executable.contains("/\($0)") }
            || executable.contains(".app/contents/macos/portharbor")
    }
}

public struct TerminationPlanner: Sendable {
    private let policy: SafetyPolicy

    public init(policy: SafetyPolicy = SafetyPolicy()) {
        self.policy = policy
    }

    public func plan(
        service: DiscoveredService,
        authorization: StopAuthorization
    ) throws -> TerminationPlan {
        if case let .denied(reason) = policy.evaluate(service: service) {
            throw StopPlanningError.ineligible(reason)
        }

        let signal: StopSignal
        switch authorization {
        case .graceful:
            signal = .terminate
        case .forceKillExplicitlyConfirmed:
            signal = .kill
        }

        let process = service.process
        let groupMembers = [process] + service.ancestry.filter {
            $0.processGroupID == process.processGroupID
        }
        let groupIsIsolated = process.processGroupID > 1
            && process.processGroupID == process.pid
            && groupMembers.allSatisfy { !ProtectedProcessBoundary.isProtected($0) }

        let target: StopTarget
        let explanation: String
        if groupIsIsolated {
            target = .processGroup(id: process.processGroupID)
            explanation = "Signal the isolated job process group \(process.processGroupID)."
        } else {
            target = .process(pid: process.pid)
            explanation = "Signal only process \(process.pid); its process group is shared or protected."
        }

        return TerminationPlan(
            serviceID: service.id,
            expectedIdentity: process,
            target: target,
            signal: signal,
            explanation: explanation
        )
    }
}

public protocol FreshProcessInspecting: Sendable {
    func identity(for pid: Int32) async throws -> ProcessIdentity?
}

public protocol SignalDelivering: Sendable {
    func send(_ signal: StopSignal, to target: StopTarget) async throws
}

public enum StopExecutionError: Error, Equatable, Sendable {
    case processNoLongerExists
    case identityChanged
    case forceKillRequiresSeparateAuthorization
    case targetDidNotExit
}

public actor SafeStopExecutor<Inspector: FreshProcessInspecting, Delivery: SignalDelivering> {
    private let inspector: Inspector
    private let delivery: Delivery
    private let exitTimeout: Duration
    private let verificationInterval: Duration

    public init(
        inspector: Inspector,
        delivery: Delivery,
        exitTimeout: Duration = .seconds(3),
        verificationInterval: Duration = .milliseconds(100)
    ) {
        self.inspector = inspector
        self.delivery = delivery
        self.exitTimeout = exitTimeout
        self.verificationInterval = verificationInterval
    }

    public func execute(
        _ plan: TerminationPlan,
        authorization: StopAuthorization
    ) async throws {
        if plan.signal == .kill && authorization != .forceKillExplicitlyConfirmed {
            throw StopExecutionError.forceKillRequiresSeparateAuthorization
        }

        guard let fresh = try await inspector.identity(for: plan.expectedIdentity.pid) else {
            throw StopExecutionError.processNoLongerExists
        }

        guard identitiesMatch(plan.expectedIdentity, fresh) else {
            throw StopExecutionError.identityChanged
        }

        try await delivery.send(plan.signal, to: plan.target)

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: exitTimeout)
        while clock.now < deadline {
            guard let current = try await inspector.identity(
                for: plan.expectedIdentity.pid
            ) else {
                return
            }

            if !identitiesMatch(plan.expectedIdentity, current) {
                return
            }

            try? await Task.sleep(for: verificationInterval)
        }

        throw StopExecutionError.targetDidNotExit
    }

    private func identitiesMatch(
        _ expected: ProcessIdentity,
        _ fresh: ProcessIdentity
    ) -> Bool {
        guard
            expected.pid == fresh.pid,
            expected.parentPID == fresh.parentPID,
            expected.processGroupID == fresh.processGroupID,
            expected.name == fresh.name,
            expected.executablePath == fresh.executablePath,
            let expectedStart = expected.startTime,
            let freshStart = fresh.startTime
        else {
            return false
        }

        return abs(expectedStart.timeIntervalSince(freshStart)) < 1
    }
}

public struct DarwinSignalDelivery: SignalDelivering {
    public init() {}

    public func send(_ signal: StopSignal, to target: StopTarget) async throws {
        let result: Int32
        switch target {
        case let .process(pid):
            result = Darwin.kill(pid, signal.rawValue)
        case let .processGroup(id):
            result = Darwin.kill(-id, signal.rawValue)
        }

        if result != 0 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
