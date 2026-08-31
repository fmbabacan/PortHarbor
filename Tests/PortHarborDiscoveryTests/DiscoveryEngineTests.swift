import Foundation
import Testing
import PortHarborCore
@testable import PortHarborDiscovery

private struct FailingProvider: ServiceDiscovering {
    struct Failure: Error {}

    func discover() async throws -> ServiceSnapshot {
        throw Failure()
    }
}

private struct SnapshotProvider: ServiceDiscovering {
    let snapshot: ServiceSnapshot

    func discover() async throws -> ServiceSnapshot {
        snapshot
    }
}

private actor SuspendedHealthEnricher: SnapshotHealthEnriching {
    private var continuation: CheckedContinuation<Void, Never>?
    private var started = false

    func enrich(_ snapshot: ServiceSnapshot) async -> ServiceSnapshot {
        started = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }

        return ServiceSnapshot(
            capturedAt: snapshot.capturedAt,
            services: snapshot.services.map { service in
                DiscoveredService(
                    endpoint: service.endpoint,
                    process: service.process,
                    ancestry: service.ancestry,
                    category: service.category,
                    project: service.project,
                    health: .responding
                )
            },
            isStale: snapshot.isStale,
            diagnostic: snapshot.diagnostic
        )
    }

    func hasStarted() -> Bool {
        started
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private struct StubCommandRunner: CommandRunning {
    let listenerOutput: String
    let processOutput: String
    let workingDirectoryOutput: String

    func run(executable: URL, arguments: [String]) async throws -> String {
        if executable.path == "/bin/ps" {
            return processOutput
        }
        if arguments.contains("cwd") {
            return workingDirectoryOutput
        }
        return listenerOutput
    }
}

private struct StubProjectFileInspector: ProjectFileInspecting {
    let existingPaths: Set<String>

    func itemExists(at path: String) -> Bool {
        existingPaths.contains(path)
    }
}

@Test func failedScanIsMarkedStale() async {
    let engine = DiscoveryEngine(provider: FailingProvider())
    let snapshot = await engine.scan()

    #expect(snapshot.isStale)
    #expect(snapshot.diagnostic != nil)
}

@Test func discoveryCanPublishBeforeHealthCompletes() async {
    let service = DiscoveredService(
        endpoint: ListenerEndpoint(address: "127.0.0.1", port: 3000, family: .ipv4),
        process: ProcessIdentity(
            pid: 3000,
            parentPID: 1,
            processGroupID: 3000,
            name: "node"
        ),
        category: .development
    )
    let rawSnapshot = ServiceSnapshot(services: [service])
    let healthEnricher = SuspendedHealthEnricher()
    let engine = DiscoveryEngine(
        provider: SnapshotProvider(snapshot: rawSnapshot),
        healthEnricher: healthEnricher
    )

    let discovered = await engine.discoverWithoutWaitingForHealth()

    #expect(discovered.services[0].health == .unknown)
    #expect(await engine.currentSnapshot().services[0].health == .unknown)

    let refresh = Task {
        await engine.refreshHealth()
    }

    while await healthEnricher.hasStarted() == false {
        await Task.yield()
    }

    #expect(await engine.currentSnapshot().services[0].health == .unknown)

    await healthEnricher.resume()
    let enriched = await refresh.value

    #expect(enriched.services[0].health == .responding)
    #expect(await engine.currentSnapshot().services[0].health == .responding)
}

@Test func snapshotSubscribersShareTheSamePublishedValues() async {
    let service = DiscoveredService(
        endpoint: ListenerEndpoint(address: "127.0.0.1", port: 4100, family: .ipv4),
        process: ProcessIdentity(
            pid: 4100,
            parentPID: 1,
            processGroupID: 4100,
            name: "node"
        ),
        category: .development
    )
    let snapshot = ServiceSnapshot(
        capturedAt: Date(timeIntervalSince1970: 4_100),
        services: [service]
    )
    let engine = DiscoveryEngine(provider: SnapshotProvider(snapshot: snapshot))
    let firstStream = await engine.snapshots()
    let secondStream = await engine.snapshots()
    var firstIterator = firstStream.makeAsyncIterator()
    var secondIterator = secondStream.makeAsyncIterator()

    let firstInitial = await firstIterator.next()
    let secondInitial = await secondIterator.next()

    _ = await engine.discoverWithoutWaitingForHealth()
    let firstPublished = await firstIterator.next()
    let secondPublished = await secondIterator.next()

    #expect(firstInitial == .empty)
    #expect(secondInitial == .empty)
    #expect(firstPublished == snapshot)
    #expect(secondPublished == snapshot)
}

@Test func lsofParserReadsIPv4IPv6AndWildcardListeners() {
    let output = """
    p622
    crapportd
    f10
    tIPv4
    n*:56787
    TST=LISTEN
    p856
    cnode
    f14
    tIPv4
    n127.0.0.1:8232
    TST=LISTEN
    p900
    cpython3
    f8
    tIPv6
    n[::1]:8080
    TST=LISTEN
    """

    let listeners = LsofFieldParser().parse(output)

    #expect(listeners.count == 3)
    #expect(listeners[0].pid == 622)
    #expect(listeners[0].endpoint.address == "*")
    #expect(listeners[0].endpoint.port == 56_787)
    #expect(listeners[0].endpoint.family == .ipv4)
    #expect(listeners[1].processName == "node")
    #expect(listeners[1].endpoint.exposure == .onlyThisMac)
    #expect(listeners[2].endpoint.address == "::1")
    #expect(listeners[2].endpoint.family == .ipv6)
}

@Test func lsofTypeFieldDistinguishesWildcardFamilies() {
    let output = """
    p622
    crapportd
    f10
    tIPv4
    n*:56787
    TST=LISTEN
    f11
    tIPv6
    n*:56787
    TST=LISTEN
    """

    let listeners = LsofFieldParser().parse(output)

    #expect(listeners.count == 2)
    #expect(listeners[0].endpoint.family == .ipv4)
    #expect(listeners[1].endpoint.family == .ipv6)
    #expect(listeners[0].endpoint.address == "*")
    #expect(listeners[1].endpoint.address == "*")
}

@Test func providerCreatesSortedClassifiedSnapshot() async throws {
    let output = """
    p30
    cfigma_agent
    f3
    tIPv4
    n127.0.0.1:44950
    TST=LISTEN
    p20
    cnode
    f4
    tIPv4
    n127.0.0.1:3000
    TST=LISTEN
    """
    let provider = LsofListenerProvider(
        runner: StubCommandRunner(
            listenerOutput: output,
            processOutput: """
              1 0 1 Wed Aug 19 17:53:22 2026 /sbin/launchd
             20 1 18 Sun Aug 30 17:00:01 2026 /opt/homebrew/bin/node
             30 1 30 Sat Aug 29 09:11:51 2026 /Applications/FigmaAgent.app/Contents/MacOS/figma_agent
            """,
            workingDirectoryOutput: """
            p20
            n/
            p30
            n/
            """
        )
    )

    let snapshot = try await provider.discover()

    #expect(snapshot.services.count == 2)
    #expect(snapshot.services[0].endpoint.port == 3_000)
    #expect(snapshot.services[0].category == .development)
    #expect(snapshot.services[0].process.parentPID == 1)
    #expect(snapshot.services[0].process.processGroupID == 18)
    #expect(snapshot.services[0].process.executablePath == "/opt/homebrew/bin/node")
    #expect(snapshot.services[0].ancestry.map(\.pid) == [1])
    #expect(snapshot.services[1].category == .background)
    #expect(snapshot.isStale == false)
}

@Test func workingDirectoryParserMapsProcesses() {
    let output = """
    p20
    fcwd
    n/Users/example/projects/harbor
    p30
    fcwd
    n/
    """

    let directories = WorkingDirectoryParser().parse(output)

    #expect(directories[20] == "/Users/example/projects/harbor")
    #expect(directories[30] == "/")
}

@Test func projectResolverFindsNearestRootAndExplainsConfidence() {
    let resolver = ProjectResolver(
        inspector: StubProjectFileInspector(existingPaths: [
            "/Users/example/projects/harbor/.git",
            "/Users/example/projects/harbor/package.json",
            "/Users/example/projects/harbor/next.config.mjs"
        ])
    )
    let process = ProcessIdentity(
        pid: 20,
        parentPID: 1,
        processGroupID: 20,
        name: "node"
    )

    let match = resolver.resolve(
        workingDirectory: "/Users/example/projects/harbor/apps/web",
        process: process,
        ancestry: []
    )

    #expect(match?.name == "harbor")
    #expect(match?.rootPath == "/Users/example/projects/harbor")
    #expect(match?.confidence == 1)
    #expect(match?.evidence.contains { $0.summary == "Found package.json" } == true)
    #expect(match?.evidence.contains { $0.kind == .command } == true)
}

@Test func projectResolverRejectsRootAndWeakDirectories() {
    let resolver = ProjectResolver(
        inspector: StubProjectFileInspector(existingPaths: [])
    )
    let process = ProcessIdentity(
        pid: 20,
        parentPID: 1,
        processGroupID: 20,
        name: "node"
    )

    #expect(resolver.resolve(workingDirectory: "/", process: process, ancestry: []) == nil)
    #expect(
        resolver.resolve(
            workingDirectory: "/Users/example/Downloads",
            process: process,
            ancestry: []
        ) == nil
    )
}

@Test func processParserReadsIdentityAndResolvesAncestry() {
    let output = """
        1     0     1 Wed Aug 19 17:53:22 2026 /sbin/launchd
      700     1   700 Sun Aug 30 16:59:58 2026 /bin/zsh
      710   700   700 Sun Aug 30 17:00:00 2026 /opt/homebrew/bin/npm
      720   710   700 Sun Aug 30 17:00:01 2026 /opt/homebrew/bin/node
    """

    let table = PSProcessParser().parse(output)
    let node = table[720]

    #expect(node?.parentPID == 710)
    #expect(node?.processGroupID == 700)
    #expect(node?.name == "node")
    #expect(node?.startTime != nil)
    #expect(table.ancestry(for: 720).map(\.pid) == [710, 700, 1])
}

@Test func ancestryResolutionStopsAtCyclesAndDepthLimit() {
    let processes = [
        ProcessIdentity(pid: 10, parentPID: 20, processGroupID: 10, name: "a"),
        ProcessIdentity(pid: 20, parentPID: 10, processGroupID: 10, name: "b")
    ]
    let table = ProcessTable(processes: processes)

    #expect(table.ancestry(for: 10).map(\.pid) == [20])
    #expect(table.ancestry(for: 10, maximumDepth: 0).isEmpty)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["PORTHARBOR_LIVE_TEST"] == "1"))
func liveProviderDiscoversCurrentMacListeners() async throws {
    let snapshot = try await LsofListenerProvider().discover()

    #expect(snapshot.isStale == false)
    #expect(snapshot.services.isEmpty == false)
    #expect(snapshot.services.allSatisfy { $0.endpoint.port > 0 })
    #expect(snapshot.services.contains { $0.endpoint.family == .ipv4 })
}
