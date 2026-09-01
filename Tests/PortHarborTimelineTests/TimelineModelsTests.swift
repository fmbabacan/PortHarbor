import Foundation
import Testing
import PortHarborCore
@testable import PortHarborTimeline

private func timelineService(
    pid: Int32 = 42,
    address: String = "127.0.0.1",
    port: UInt16 = 3000,
    health: ServiceHealth = .unknown,
    project: ProjectMatch? = nil
) -> DiscoveredService {
    DiscoveredService(
        endpoint: ListenerEndpoint(address: address, port: port, family: .ipv4),
        process: ProcessIdentity(
            pid: pid,
            parentPID: 1,
            processGroupID: pid,
            name: "node",
            executablePath: "/usr/local/bin/node",
            startTime: Date(timeIntervalSince1970: 100)
        ),
        category: .development,
        project: project,
        health: health
    )
}

@Test func timelineEventContainsOnlySanitizedDisplayData() {
    let event = TimelineEvent(
        occurredAt: Date(timeIntervalSince1970: 1_000),
        kind: .serviceStarted,
        serviceID: "42:ipv4:127.0.0.1:3000",
        summary: "Example started on port 3000"
    )

    #expect(event.kind == .serviceStarted)
    #expect(event.summary == "Example started on port 3000")
}

@Test func timelineDiffRecordsOnlyMeaningfulChanges() {
    let date = Date(timeIntervalSince1970: 2_000)
    let oldService = timelineService(health: .unknown)
    let newService = timelineService(health: .responding)
    let events = TimelineDiff().events(
        from: ServiceSnapshot(capturedAt: date.addingTimeInterval(-1), services: [oldService]),
        to: ServiceSnapshot(capturedAt: date, services: [newService])
    )

    #expect(events.count == 1)
    #expect(events[0].kind == .healthChanged)
    #expect(events[0].summary.contains("/usr/local/bin") == false)
}

@Test func timelineDiffDetectsPortOwnershipChange() {
    let date = Date(timeIntervalSince1970: 3_000)
    let previous = timelineService(pid: 42)
    let current = timelineService(pid: 84)
    let events = TimelineDiff().events(
        from: ServiceSnapshot(services: [previous]),
        to: ServiceSnapshot(capturedAt: date, services: [current])
    )

    #expect(events.contains { $0.kind == .portOwnerChanged })
    let owner = events.first { $0.kind == .portOwnerChanged }
    #expect(owner?.port == 3000)
    #expect(owner?.context?.previousProcessID == 42)
    #expect(owner?.context?.processID == 84)
}

@Test func activityGroupsBindAddressChangesUnderOnePort() {
    let previous = timelineService(address: "127.0.0.1")
    let current = timelineService(address: "0.0.0.0")
    let events = TimelineDiff().events(
        from: ServiceSnapshot(services: [previous]),
        to: ServiceSnapshot(services: [current])
    )
    let endpointChange = events.first { $0.kind == .endpointChanged }
    #expect(endpointChange?.portID == "tcp:3000")
    #expect(endpointChange?.context?.endpointID == "tcp:ipv4:0.0.0.0:3000")
}

@Test func oldTimelineJSONDecodesAndInfersPortIdentity() throws {
    let json = """
    [{"id":"00000000-0000-0000-0000-000000000001","occurredAt":"1970-01-01T00:16:40Z","kind":"serviceStarted","serviceID":"42:ipv4:127.0.0.1:3000","summary":"Example started on port 3000"}]
    """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let events = try decoder.decode([TimelineEvent].self, from: Data(json.utf8))
    #expect(events.first?.port == 3000)
    #expect(events.first?.portID == "tcp:3000")
}

@Test func timelineStoreQueriesEventsByLogicalPort() async {
    let base = Date(timeIntervalSince1970: 8_000)
    let store = TimelineStore(persistence: InMemoryTimelinePersistence(), retention: 60)
    _ = await store.ingest(ServiceSnapshot(capturedAt: base, services: []), now: base)
    _ = await store.ingest(
        ServiceSnapshot(capturedAt: base.addingTimeInterval(1), services: [timelineService(port: 3000)]),
        now: base.addingTimeInterval(1)
    )
    _ = await store.ingest(
        ServiceSnapshot(capturedAt: base.addingTimeInterval(2), services: [timelineService(port: 4000)]),
        now: base.addingTimeInterval(2)
    )
    let events = await store.events(forPort: 3000, now: base.addingTimeInterval(2))
    #expect(!events.isEmpty)
    #expect(events.allSatisfy { $0.port == 3000 })
}

@Test func timelineStoreEnforcesRetentionAndSupportsClearing() async throws {
    let now = Date(timeIntervalSince1970: 100_000)
    let expired = TimelineEvent(
        occurredAt: now.addingTimeInterval(-(25 * 60 * 60)),
        kind: .serviceStarted,
        serviceID: "expired",
        summary: "Expired"
    )
    let retained = TimelineEvent(
        occurredAt: now.addingTimeInterval(-(23 * 60 * 60)),
        kind: .serviceStarted,
        serviceID: "retained",
        summary: "Retained"
    )
    let persistence = InMemoryTimelinePersistence(events: [expired, retained])
    let store = TimelineStore(persistence: persistence)

    await store.restore(now: now)
    #expect(await store.currentEvents(now: now).map(\.serviceID) == ["retained"])

    await store.clear()
    #expect(await store.currentEvents(now: now).isEmpty)
    #expect(try await persistence.load().isEmpty)
}

@Test func timelineStoreCoalescesRepeatedEvents() async {
    let base = Date(timeIntervalSince1970: 5_000)
    let persistence = InMemoryTimelinePersistence()
    let store = TimelineStore(persistence: persistence, coalescingWindow: 30)
    let empty = ServiceSnapshot(capturedAt: base, services: [])
    let active = ServiceSnapshot(
        capturedAt: base.addingTimeInterval(1),
        services: [timelineService()]
    )

    _ = await store.ingest(empty, now: base)
    _ = await store.ingest(active, now: base.addingTimeInterval(1))
    _ = await store.ingest(empty, now: base.addingTimeInterval(2))
    _ = await store.ingest(active, now: base.addingTimeInterval(3))

    let starts = await store.currentEvents(now: base.addingTimeInterval(3))
        .filter { $0.kind == .serviceStarted }
    #expect(starts.count == 1)
}

@Test func JSONFilePersistenceSurvivesRecreationAndClears() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let fileURL = directory.appendingPathComponent("timeline.json")
    let event = TimelineEvent(
        occurredAt: Date(timeIntervalSince1970: 10_000),
        kind: .serviceStarted,
        serviceID: "persistent-service",
        summary: "Example started on port 3000"
    )

    let writer = JSONFileTimelinePersistence(fileURL: fileURL)
    try await writer.save([event])

    let reader = JSONFileTimelinePersistence(fileURL: fileURL)
    #expect(try await reader.load() == [event])

    try await reader.clear()
    #expect(try await reader.load().isEmpty)
    #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)
}

@Test func restoredFileTimelineDropsExpiredEvents() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let now = Date(timeIntervalSince1970: 200_000)
    let persistence = JSONFileTimelinePersistence(
        fileURL: directory.appendingPathComponent("timeline.json")
    )
    try await persistence.save([
        TimelineEvent(
            occurredAt: now.addingTimeInterval(-(25 * 60 * 60)),
            kind: .serviceStopped,
            serviceID: "expired",
            summary: "Expired"
        ),
        TimelineEvent(
            occurredAt: now.addingTimeInterval(-(2 * 60 * 60)),
            kind: .serviceStarted,
            serviceID: "current",
            summary: "Current"
        )
    ])

    let store = TimelineStore(persistence: persistence)
    await store.restore(now: now)

    #expect(await store.currentEvents(now: now).map(\.serviceID) == ["current"])
    #expect(try await persistence.load().map(\.serviceID) == ["current"])
}
