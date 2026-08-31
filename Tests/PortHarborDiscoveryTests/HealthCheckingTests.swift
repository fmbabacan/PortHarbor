import Foundation
import Testing
import PortHarborCore
@testable import PortHarborDiscovery

private actor StubHealthChecker: ServiceHealthChecking {
    private var checks = 0
    let health: ServiceHealth

    init(health: ServiceHealth) {
        self.health = health
    }

    func check(service: DiscoveredService) async -> ServiceHealth {
        checks += 1
        return health
    }

    func checkCount() -> Int {
        checks
    }
}

private func healthTestService(port: UInt16 = 3000) -> DiscoveredService {
    DiscoveredService(
        endpoint: ListenerEndpoint(
            address: "127.0.0.1",
            port: port,
            family: .ipv4
        ),
        process: ProcessIdentity(
            pid: Int32(port),
            parentPID: 1,
            processGroupID: Int32(port),
            name: "node"
        ),
        category: .development
    )
}

@Test func healthEnricherPreservesIdentityAndAppliesResult() async {
    let checker = StubHealthChecker(health: .responding)
    let enricher = HealthEnricher(checker: checker)
    let service = healthTestService()
    let capturedAt = Date(timeIntervalSince1970: 1234)
    let snapshot = ServiceSnapshot(capturedAt: capturedAt, services: [service])

    let enriched = await enricher.enrich(snapshot)

    #expect(enriched.capturedAt == capturedAt)
    #expect(enriched.services.count == 1)
    #expect(enriched.services[0].id == service.id)
    #expect(enriched.services[0].health == .responding)
}

@Test func healthEnricherUsesShortLivedCache() async {
    let checker = StubHealthChecker(health: .responding)
    let enricher = HealthEnricher(
        checker: checker,
        cacheDuration: .seconds(30),
        maximumConcurrency: 2
    )
    let snapshot = ServiceSnapshot(services: [healthTestService()])

    _ = await enricher.enrich(snapshot)
    _ = await enricher.enrich(snapshot)

    #expect(await checker.checkCount() == 1)
}

@Test func healthEnricherChecksEveryUncachedService() async {
    let checker = StubHealthChecker(health: .unknown)
    let enricher = HealthEnricher(
        checker: checker,
        cacheDuration: .zero,
        maximumConcurrency: 2
    )
    let snapshot = ServiceSnapshot(services: [
        healthTestService(port: 3000),
        healthTestService(port: 3001),
        healthTestService(port: 3002)
    ])

    let enriched = await enricher.enrich(snapshot)

    #expect(enriched.services.allSatisfy { $0.health == .unknown })
    #expect(await checker.checkCount() == 3)
}
