import Foundation
import PortHarborCore

public enum TimelineEventKind: String, Codable, Sendable {
    case serviceStarted
    case serviceStopped
    case portOwnerChanged
    case healthChanged
    case exposureChanged
    case projectChanged
    case endpointChanged
}

public enum ActivityRetention: String, Codable, CaseIterable, Sendable {
    case oneDay
    case sevenDays
    case thirtyDays

    public var duration: TimeInterval {
        switch self {
        case .oneDay: 24 * 60 * 60
        case .sevenDays: 7 * 24 * 60 * 60
        case .thirtyDays: 30 * 24 * 60 * 60
        }
    }
}

public struct ActivityContext: Codable, Equatable, Sendable {
    public let port: UInt16?
    public let portID: String?
    public let endpointID: String?
    public let serviceInstanceID: String?
    public let address: String?
    public let family: IPFamily?
    public let processName: String?
    public let processID: Int32?
    public let previousProcessName: String?
    public let previousProcessID: Int32?
    public let projectName: String?
    public let previousProjectName: String?
    public let health: ServiceHealth?
    public let previousHealth: ServiceHealth?
    public let exposure: NetworkExposure?
    public let previousExposure: NetworkExposure?

    public init(
        port: UInt16? = nil, portID: String? = nil, endpointID: String? = nil,
        serviceInstanceID: String? = nil, address: String? = nil, family: IPFamily? = nil,
        processName: String? = nil, processID: Int32? = nil,
        previousProcessName: String? = nil, previousProcessID: Int32? = nil,
        projectName: String? = nil, previousProjectName: String? = nil,
        health: ServiceHealth? = nil, previousHealth: ServiceHealth? = nil,
        exposure: NetworkExposure? = nil, previousExposure: NetworkExposure? = nil
    ) {
        self.port = port
        self.portID = portID
        self.endpointID = endpointID
        self.serviceInstanceID = serviceInstanceID
        self.address = address
        self.family = family
        self.processName = processName
        self.processID = processID
        self.previousProcessName = previousProcessName
        self.previousProcessID = previousProcessID
        self.projectName = projectName
        self.previousProjectName = previousProjectName
        self.health = health
        self.previousHealth = previousHealth
        self.exposure = exposure
        self.previousExposure = previousExposure
    }
}

public struct TimelineEvent: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let occurredAt: Date
    public let kind: TimelineEventKind
    public let serviceID: String
    public let summary: String
    public let context: ActivityContext?

    public init(
        id: UUID = UUID(),
        occurredAt: Date = Date(),
        kind: TimelineEventKind,
        serviceID: String,
        summary: String,
        context: ActivityContext? = nil
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.kind = kind
        self.serviceID = serviceID
        self.summary = summary
        self.context = context
    }

    public var port: UInt16? {
        context?.port ?? Self.legacyPort(from: serviceID)
    }

    public var portID: String? {
        context?.portID ?? port.map { "tcp:\($0)" }
    }

    private static func legacyPort(from serviceID: String) -> UInt16? {
        guard let component = serviceID.split(separator: ":").last else { return nil }
        return UInt16(component)
    }
}

public struct TimelineDiff: Sendable {
    public init() {}

    public func events(
        from previous: ServiceSnapshot,
        to current: ServiceSnapshot,
        occurredAt: Date? = nil
    ) -> [TimelineEvent] {
        let eventDate = occurredAt ?? current.capturedAt
        let previousByID = Dictionary(uniqueKeysWithValues: previous.services.map { ($0.id, $0) })
        let currentByID = Dictionary(uniqueKeysWithValues: current.services.map { ($0.id, $0) })
        var events: [TimelineEvent] = []

        for service in current.services where previousByID[service.id] == nil {
            events.append(
                makeEvent(
                    kind: .serviceStarted,
                    service: service,
                    occurredAt: eventDate,
                    summary: "\(displayName(for: service)) started on port \(service.endpoint.port)"
                )
            )
        }

        for service in previous.services where currentByID[service.id] == nil {
            events.append(
                makeEvent(
                    kind: .serviceStopped,
                    service: service,
                    occurredAt: eventDate,
                    summary: "\(displayName(for: service)) stopped on port \(service.endpoint.port)"
                )
            )
        }

        let previousByEndpoint = Dictionary(
            previous.services.map { (endpointKey(for: $0), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for service in current.services {
            guard let oldService = previousByEndpoint[endpointKey(for: service)] else { continue }

            if oldService.process.pid != service.process.pid
                || oldService.process.name != service.process.name {
                events.append(
                    makeEvent(
                        kind: .portOwnerChanged,
                        service: service,
                        occurredAt: eventDate,
                        summary: "Port \(service.endpoint.port) ownership changed from \(displayName(for: oldService)) to \(displayName(for: service))",
                        previous: oldService
                    )
                )
                continue
            }

            if oldService.health != service.health {
                events.append(
                    makeEvent(
                        kind: .healthChanged,
                        service: service,
                        occurredAt: eventDate,
                        summary: "\(displayName(for: service)) health changed from \(oldService.health.rawValue) to \(service.health.rawValue)",
                        previous: oldService
                    )
                )
            }

            if oldService.endpoint.exposure != service.endpoint.exposure {
                events.append(
                    makeEvent(
                        kind: .exposureChanged,
                        service: service,
                        occurredAt: eventDate,
                        summary: "\(displayName(for: service)) exposure changed from \(oldService.endpoint.exposure.rawValue) to \(service.endpoint.exposure.rawValue)",
                        previous: oldService
                    )
                )
            }

            if projectIdentity(oldService.project) != projectIdentity(service.project) {
                events.append(
                    makeEvent(
                        kind: .projectChanged,
                        service: service,
                        occurredAt: eventDate,
                        summary: "\(displayName(for: service)) project association changed",
                        previous: oldService
                    )
                )
            }
        }

        let previousByPort = Dictionary(grouping: previous.services, by: { $0.portID })
        let currentByPort = Dictionary(grouping: current.services, by: { $0.portID })
        for (portID, currentServices) in currentByPort {
            guard let oldServices = previousByPort[portID] else { continue }
            let oldEndpoints = Set(oldServices.map(\.endpointID))
            let newEndpoints = Set(currentServices.map(\.endpointID))
            guard oldEndpoints != newEndpoints, let service = currentServices.first else { continue }
            let existingKinds = events.filter { $0.portID == portID }.map(\.kind)
            if !existingKinds.contains(.portOwnerChanged) {
                events.append(makeEvent(
                    kind: .endpointChanged,
                    service: service,
                    occurredAt: eventDate,
                    summary: "Port \(service.endpoint.port) endpoint changed",
                    previous: oldServices.first
                ))
            }
        }

        return events.sorted {
            if $0.serviceID == $1.serviceID {
                return $0.kind.rawValue < $1.kind.rawValue
            }
            return $0.serviceID < $1.serviceID
        }
    }

    private func endpointKey(for service: DiscoveredService) -> String {
        "\(service.endpoint.family.rawValue):\(service.endpoint.address):\(service.endpoint.port)"
    }

    private func projectIdentity(_ project: ProjectMatch?) -> String? {
        project.map { "\($0.name):\($0.rootPath)" }
    }

    private func displayName(for service: DiscoveredService) -> String {
        service.project?.name ?? service.process.name
    }

    private func makeEvent(
        kind: TimelineEventKind,
        service: DiscoveredService,
        occurredAt: Date,
        summary: String,
        previous: DiscoveredService? = nil
    ) -> TimelineEvent {
        TimelineEvent(
            occurredAt: occurredAt,
            kind: kind,
            serviceID: service.id,
            summary: summary,
            context: ActivityContext(
                port: service.endpoint.port,
                portID: service.portID,
                endpointID: service.endpointID,
                serviceInstanceID: service.serviceInstanceID,
                address: service.endpoint.address,
                family: service.endpoint.family,
                processName: service.process.name,
                processID: service.process.pid,
                previousProcessName: previous?.process.name,
                previousProcessID: previous?.process.pid,
                projectName: service.project?.name,
                previousProjectName: previous?.project?.name,
                health: service.health,
                previousHealth: previous?.health,
                exposure: service.endpoint.exposure,
                previousExposure: previous?.endpoint.exposure
            )
        )
    }
}

public protocol TimelinePersisting: Sendable {
    func load() async throws -> [TimelineEvent]
    func save(_ events: [TimelineEvent]) async throws
    func clear() async throws
}

public actor InMemoryTimelinePersistence: TimelinePersisting {
    private var events: [TimelineEvent]

    public init(events: [TimelineEvent] = []) {
        self.events = events
    }

    public func load() async throws -> [TimelineEvent] {
        events
    }

    public func save(_ events: [TimelineEvent]) async throws {
        self.events = events
    }

    public func clear() async throws {
        events = []
    }
}

public actor JSONFileTimelinePersistence: TimelinePersisting {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public static func applicationSupport(
        fileManager: FileManager = .default
    ) throws -> JSONFileTimelinePersistence {
        let root = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = root.appendingPathComponent(
            "PortHarbor",
            isDirectory: true
        )
        return JSONFileTimelinePersistence(
            fileURL: directory.appendingPathComponent("timeline.json")
        )
    }

    public func load() async throws -> [TimelineEvent] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        return try decoder.decode(
            [TimelineEvent].self,
            from: Data(contentsOf: fileURL)
        )
    }

    public func save(_ events: [TimelineEvent]) async throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try encoder.encode(events).write(
            to: fileURL,
            options: [.atomic, .completeFileProtectionUnlessOpen]
        )
    }

    public func clear() async throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }
        try FileManager.default.removeItem(at: fileURL)
    }
}

public actor TimelineStore<Persistence: TimelinePersisting> {
    private let persistence: Persistence
    private let retention: TimeInterval
    private let coalescingWindow: TimeInterval
    private let diff = TimelineDiff()
    private var events: [TimelineEvent] = []
    private var previousSnapshot: ServiceSnapshot?

    public init(
        persistence: Persistence,
        retention: TimeInterval = 24 * 60 * 60,
        coalescingWindow: TimeInterval = 30
    ) {
        self.persistence = persistence
        self.retention = retention
        self.coalescingWindow = coalescingWindow
    }

    public func restore(now: Date = Date()) async {
        do {
            events = retained(try await persistence.load(), now: now)
            try await persistence.save(events)
        } catch {
            events = []
        }
    }

    @discardableResult
    public func ingest(
        _ snapshot: ServiceSnapshot,
        now: Date? = nil
    ) async -> [TimelineEvent] {
        let eventDate = now ?? snapshot.capturedAt
        defer { previousSnapshot = snapshot }

        guard let previousSnapshot else {
            events = retained(events, now: eventDate)
            await persistBestEffort()
            return []
        }

        let additions = diff.events(
            from: previousSnapshot,
            to: snapshot,
            occurredAt: eventDate
        )

        for event in additions where shouldAppend(event) {
            events.append(event)
        }

        events = retained(events, now: eventDate)
            .sorted { $0.occurredAt > $1.occurredAt }
        await persistBestEffort()
        return additions
    }

    public func currentEvents(now: Date = Date()) -> [TimelineEvent] {
        retained(events, now: now).sorted { $0.occurredAt > $1.occurredAt }
    }

    public func events(forPort port: UInt16, now: Date = Date()) -> [TimelineEvent] {
        currentEvents(now: now).filter { $0.port == port }
    }

    public func clear() async {
        events = []
        do {
            try await persistence.clear()
        } catch {
            // Timeline persistence failures must not interrupt live discovery.
        }
    }

    private func shouldAppend(_ event: TimelineEvent) -> Bool {
        guard let latest = events
            .filter({ $0.kind == event.kind && $0.serviceID == event.serviceID })
            .max(by: { $0.occurredAt < $1.occurredAt })
        else {
            return true
        }

        return event.occurredAt.timeIntervalSince(latest.occurredAt) > coalescingWindow
            || latest.summary != event.summary
    }

    private func retained(_ source: [TimelineEvent], now: Date) -> [TimelineEvent] {
        let cutoff = now.addingTimeInterval(-retention)
        return source.filter { $0.occurredAt >= cutoff && $0.occurredAt <= now }
    }

    private func persistBestEffort() async {
        do {
            try await persistence.save(events)
        } catch {
            // Timeline persistence is intentionally isolated from discovery.
        }
    }
}
