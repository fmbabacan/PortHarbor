import Foundation
import Testing
import PortHarborCore
@testable import PortHarborSafety

private actor StubInspector: FreshProcessInspecting {
    private var identities: [ProcessIdentity?]

    init(identity: ProcessIdentity?) {
        identities = [identity]
    }

    init(identities: [ProcessIdentity?]) {
        self.identities = identities
    }

    func identity(for pid: Int32) async throws -> ProcessIdentity? {
        guard identities.count > 1 else { return identities.first ?? nil }
        return identities.removeFirst()
    }
}

private actor RecordingDelivery: SignalDelivering {
    private var deliveries: [(StopSignal, StopTarget)] = []

    func send(_ signal: StopSignal, to target: StopTarget) async throws {
        deliveries.append((signal, target))
    }

    func count() -> Int {
        deliveries.count
    }

    func lastSignal() -> StopSignal? {
        deliveries.last?.0
    }
}

private func process(
    pid: Int32 = 200,
    parentPID: Int32 = 100,
    processGroupID: Int32 = 200,
    name: String = "node",
    startTime: Date = Date(timeIntervalSince1970: 1_000)
) -> ProcessIdentity {
    ProcessIdentity(
        pid: pid,
        parentPID: parentPID,
        processGroupID: processGroupID,
        name: name,
        executablePath: "/usr/local/bin/\(name)",
        startTime: startTime
    )
}

private func service(
    process identity: ProcessIdentity = process(),
    ancestry: [ProcessIdentity] = [],
    category: ServiceCategory = .development
) -> DiscoveredService {
    DiscoveredService(
        endpoint: ListenerEndpoint(address: "127.0.0.1", port: 3000, family: .ipv4),
        process: identity,
        ancestry: ancestry,
        category: category
    )
}

@Test func policyDeniesSystemService() {
    let service = DiscoveredService(
        endpoint: ListenerEndpoint(address: "*", port: 22, family: .ipv4),
        process: ProcessIdentity(
            pid: 42,
            parentPID: 1,
            processGroupID: 42,
            name: "sshd",
            executablePath: "/usr/sbin/sshd",
            startTime: Date(timeIntervalSince1970: 1_000)
        ),
        category: .system
    )

    #expect(
        SafetyPolicy().evaluate(service: service)
            == .denied(reason: "System services cannot be stopped by PortHarbor.")
    )
}

@Test func policyDeniesProtectedShellAncestry() {
    let candidate = service(
        ancestry: [process(pid: 100, parentPID: 1, processGroupID: 100, name: "zsh")]
    )

    #expect(
        SafetyPolicy().evaluate(service: candidate)
            == .denied(reason: "The process tree crosses protected boundary zsh.")
    )
}

@Test func plannerTargetsIsolatedJobGroupWithSIGTERM() throws {
    let candidate = service()
    let plan = try TerminationPlanner().plan(
        service: candidate,
        authorization: .graceful
    )

    #expect(plan.target == .processGroup(id: 200))
    #expect(plan.signal == .terminate)
}

@Test func plannerUsesSingleProcessWhenGroupIsShared() throws {
    let identity = process(processGroupID: 100)
    let plan = try TerminationPlanner().plan(
        service: service(process: identity),
        authorization: .graceful
    )

    #expect(plan.target == .process(pid: 200))
}

@Test func executorRejectsReusedPIDWithoutDeliveringSignal() async throws {
    let expected = process()
    let reused = process(startTime: Date(timeIntervalSince1970: 2_000))
    let delivery = RecordingDelivery()
    let executor = SafeStopExecutor(
        inspector: StubInspector(identity: reused),
        delivery: delivery
    )
    let plan = try TerminationPlanner().plan(
        service: service(process: expected),
        authorization: .graceful
    )

    await #expect(throws: StopExecutionError.identityChanged) {
        try await executor.execute(plan, authorization: .graceful)
    }
    #expect(await delivery.count() == 0)
}

@Test func executorDeliversSIGTERMAfterFreshIdentityValidation() async throws {
    let identity = process()
    let delivery = RecordingDelivery()
    let executor = SafeStopExecutor(
        inspector: StubInspector(identity: identity),
        delivery: delivery,
        exitTimeout: .zero
    )
    let plan = try TerminationPlanner().plan(
        service: service(process: identity),
        authorization: .graceful
    )

    await #expect(throws: StopExecutionError.targetDidNotExit) {
        try await executor.execute(plan, authorization: .graceful)
    }

    #expect(await delivery.count() == 1)
    #expect(await delivery.lastSignal() == .terminate)
}

@Test func executorReportsSuccessOnlyAfterTargetExits() async throws {
    let identity = process()
    let delivery = RecordingDelivery()
    let executor = SafeStopExecutor(
        inspector: StubInspector(identities: [identity, nil]),
        delivery: delivery,
        exitTimeout: .seconds(1),
        verificationInterval: .zero
    )
    let plan = try TerminationPlanner().plan(
        service: service(process: identity),
        authorization: .graceful
    )

    try await executor.execute(plan, authorization: .graceful)

    #expect(await delivery.count() == 1)
}

@Test func SIGKILLRequiresSeparateExecutionAuthorization() async throws {
    let identity = process()
    let delivery = RecordingDelivery()
    let executor = SafeStopExecutor(
        inspector: StubInspector(identity: identity),
        delivery: delivery,
        exitTimeout: .zero
    )
    let plan = try TerminationPlanner().plan(
        service: service(process: identity),
        authorization: .forceKillExplicitlyConfirmed
    )

    await #expect(throws: StopExecutionError.forceKillRequiresSeparateAuthorization) {
        try await executor.execute(plan, authorization: .graceful)
    }
    #expect(await delivery.count() == 0)

    await #expect(throws: StopExecutionError.targetDidNotExit) {
        try await executor.execute(
            plan,
            authorization: .forceKillExplicitlyConfirmed
        )
    }
    #expect(await delivery.lastSignal() == .kill)
}
