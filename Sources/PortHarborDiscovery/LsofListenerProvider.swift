import Foundation
import PortHarborCore

public struct RawListener: Equatable, Sendable {
    public let pid: Int32
    public let processName: String
    public let endpoint: ListenerEndpoint

    public init(pid: Int32, processName: String, endpoint: ListenerEndpoint) {
        self.pid = pid
        self.processName = processName
        self.endpoint = endpoint
    }
}

public struct LsofFieldParser: Sendable {
    public init() {}

    public func parse(_ output: String) -> [RawListener] {
        var currentPID: Int32?
        var currentProcessName = "Unavailable"
        var currentFamily: IPFamily?
        var listeners: [RawListener] = []

        for line in output.split(whereSeparator: \Character.isNewline) {
            guard let field = line.first else { continue }
            let value = String(line.dropFirst())

            switch field {
            case "p":
                currentPID = Int32(value)
                currentProcessName = "Unavailable"
                currentFamily = nil
            case "c":
                currentProcessName = value
            case "f":
                currentFamily = nil
            case "t":
                switch value {
                case "IPv4":
                    currentFamily = .ipv4
                case "IPv6":
                    currentFamily = .ipv6
                default:
                    currentFamily = nil
                }
            case "n":
                guard
                    let pid = currentPID,
                    let endpoint = parseEndpoint(value, family: currentFamily)
                else { continue }

                listeners.append(
                    RawListener(
                        pid: pid,
                        processName: currentProcessName,
                        endpoint: endpoint
                    )
                )
            default:
                continue
            }
        }

        return listeners
    }

    private func parseEndpoint(
        _ value: String,
        family explicitFamily: IPFamily?
    ) -> ListenerEndpoint? {
        guard let separator = value.lastIndex(of: ":") else { return nil }

        let rawAddress = String(value[..<separator])
        let rawPort = String(value[value.index(after: separator)...])
        guard let port = UInt16(rawPort) else { return nil }

        let address: String
        let inferredFamily: IPFamily

        if rawAddress.hasPrefix("[") && rawAddress.hasSuffix("]") {
            address = String(rawAddress.dropFirst().dropLast())
            inferredFamily = .ipv6
        } else if rawAddress.contains(":") {
            address = rawAddress
            inferredFamily = .ipv6
        } else {
            address = rawAddress
            inferredFamily = .ipv4
        }

        return ListenerEndpoint(
            address: address,
            port: port,
            family: explicitFamily ?? inferredFamily
        )
    }
}

public protocol CommandRunning: Sendable {
    func run(executable: URL, arguments: [String]) async throws -> String
}

public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(executable: URL, arguments: [String]) async throws -> String {
        try await Task.detached(priority: .utility) {
            let process = Process()
            let combinedOutput = Pipe()

            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = combinedOutput
            process.standardError = combinedOutput

            try process.run()
            let outputData = combinedOutput.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let message = String(decoding: outputData, as: UTF8.self)
                throw LsofProviderError.commandFailed(
                    status: process.terminationStatus,
                    message: message
                )
            }

            return String(decoding: outputData, as: UTF8.self)
        }.value
    }
}

public enum LsofProviderError: Error, Equatable, Sendable {
    case commandFailed(status: Int32, message: String)
}

public struct LsofListenerProvider<Runner: CommandRunning>: ServiceDiscovering {
    private let runner: Runner
    private let parser: LsofFieldParser

    public init(runner: Runner, parser: LsofFieldParser = LsofFieldParser()) {
        self.runner = runner
        self.parser = parser
    }

    public func discover() async throws -> ServiceSnapshot {
        async let listenerOutput = runner.run(
            executable: URL(fileURLWithPath: "/usr/sbin/lsof"),
            arguments: ["-nP", "-iTCP", "-sTCP:LISTEN", "-FpcfntT"]
        )

        async let processOutput = runner.run(
            executable: URL(fileURLWithPath: "/bin/ps"),
            arguments: ["-axo", "pid=,ppid=,pgid=,lstart=,comm="]
        )

        async let workingDirectoryOutput = runner.run(
            executable: URL(fileURLWithPath: "/usr/sbin/lsof"),
            arguments: ["-a", "-d", "cwd", "-Fpn"]
        )

        let listeners = parser.parse(try await listenerOutput)
        let processTable = PSProcessParser().parse(try await processOutput)
        let workingDirectories = WorkingDirectoryParser().parse(
            try await workingDirectoryOutput
        )
        let projectResolver = ProjectResolver()

        let services = listeners.map { listener in
            let process = processTable[listener.pid] ?? ProcessIdentity(
                pid: listener.pid,
                parentPID: 0,
                processGroupID: listener.pid,
                name: listener.processName
            )

            let ancestry = processTable.ancestry(for: listener.pid)
            let project = projectResolver.resolve(
                workingDirectory: workingDirectories[listener.pid],
                process: process,
                ancestry: ancestry
            )

            return DiscoveredService(
                endpoint: listener.endpoint,
                process: process,
                ancestry: ancestry,
                category: project == nil ? classify(processName: process.name) : .development,
                project: project
            )
        }

        return ServiceSnapshot(
            services: services.sorted {
                if $0.endpoint.port == $1.endpoint.port {
                    return $0.process.name.localizedStandardCompare($1.process.name) == .orderedAscending
                }
                return $0.endpoint.port < $1.endpoint.port
            }
        )
    }

    private func classify(processName: String) -> ServiceCategory {
        let normalized = processName.lowercased()

        if ["node", "bun", "deno", "python", "python3", "ruby", "php", "java", "swift", "cargo", "rustc"].contains(normalized) {
            return .development
        }

        if normalized.hasPrefix("com.apple.") || ["launchd", "rapportd", "controlcenter"].contains(normalized) {
            return .system
        }

        return .background
    }
}

public extension LsofListenerProvider where Runner == ProcessCommandRunner {
    init() {
        self.init(runner: ProcessCommandRunner())
    }
}
