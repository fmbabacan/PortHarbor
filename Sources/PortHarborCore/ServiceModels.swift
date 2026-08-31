import Foundation

public enum ServiceCategory: String, Codable, CaseIterable, Sendable {
    case development
    case background
    case system
}

public enum NetworkExposure: String, Codable, CaseIterable, Sendable {
    case onlyThisMac
    case localNetwork
    case allInterfaces

    public static func classify(address: String) -> Self {
        let normalized = address
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .lowercased()

        switch normalized {
        case "127.0.0.1", "::1", "localhost":
            return .onlyThisMac
        case "0.0.0.0", "::", "*":
            return .allInterfaces
        default:
            return .localNetwork
        }
    }
}

public enum ServiceHealth: String, Codable, CaseIterable, Sendable {
    case responding
    case starting
    case unreachable
    case unknown
}

public enum IPFamily: String, Codable, Sendable {
    case ipv4
    case ipv6
}

public struct ListenerEndpoint: Codable, Hashable, Sendable {
    public let address: String
    public let port: UInt16
    public let family: IPFamily

    public init(address: String, port: UInt16, family: IPFamily) {
        self.address = address
        self.port = port
        self.family = family
    }

    public var exposure: NetworkExposure {
        NetworkExposure.classify(address: address)
    }
}

public struct ProcessIdentity: Codable, Hashable, Sendable {
    public let pid: Int32
    public let parentPID: Int32
    public let processGroupID: Int32
    public let name: String
    public let executablePath: String?
    public let startTime: Date?

    public init(
        pid: Int32,
        parentPID: Int32,
        processGroupID: Int32,
        name: String,
        executablePath: String? = nil,
        startTime: Date? = nil
    ) {
        self.pid = pid
        self.parentPID = parentPID
        self.processGroupID = processGroupID
        self.name = name
        self.executablePath = executablePath
        self.startTime = startTime
    }
}

public struct ProjectEvidence: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case workingDirectory
        case command
        case ancestry
        case projectMarker
    }

    public let kind: Kind
    public let summary: String
    public let weight: Double

    public init(kind: Kind, summary: String, weight: Double) {
        self.kind = kind
        self.summary = summary
        self.weight = min(max(weight, 0), 1)
    }
}

public struct ProjectMatch: Codable, Hashable, Sendable {
    public let name: String
    public let rootPath: String
    public let confidence: Double
    public let evidence: [ProjectEvidence]

    public init(
        name: String,
        rootPath: String,
        confidence: Double,
        evidence: [ProjectEvidence]
    ) {
        self.name = name
        self.rootPath = rootPath
        self.confidence = min(max(confidence, 0), 1)
        self.evidence = evidence
    }
}

public struct DiscoveredService: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let endpoint: ListenerEndpoint
    public let process: ProcessIdentity
    public let ancestry: [ProcessIdentity]
    public let category: ServiceCategory
    public let project: ProjectMatch?
    public let health: ServiceHealth

    public init(
        endpoint: ListenerEndpoint,
        process: ProcessIdentity,
        ancestry: [ProcessIdentity] = [],
        category: ServiceCategory,
        project: ProjectMatch? = nil,
        health: ServiceHealth = .unknown
    ) {
        self.id = "\(process.pid):\(endpoint.family.rawValue):\(endpoint.address):\(endpoint.port)"
        self.endpoint = endpoint
        self.process = process
        self.ancestry = ancestry
        self.category = category
        self.project = project
        self.health = health
    }

    public var canStop: Bool {
        category != .system
    }
}

public struct ServiceSnapshot: Codable, Equatable, Sendable {
    public let capturedAt: Date
    public let services: [DiscoveredService]
    public let isStale: Bool
    public let diagnostic: String?

    public init(
        capturedAt: Date = Date(),
        services: [DiscoveredService],
        isStale: Bool = false,
        diagnostic: String? = nil
    ) {
        self.capturedAt = capturedAt
        self.services = services
        self.isStale = isStale
        self.diagnostic = diagnostic
    }

    public static let empty = ServiceSnapshot(
        capturedAt: .distantPast,
        services: []
    )
}

public protocol ServiceDiscovering: Sendable {
    func discover() async throws -> ServiceSnapshot
}
