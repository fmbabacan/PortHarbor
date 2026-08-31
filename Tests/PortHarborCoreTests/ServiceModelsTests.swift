import Testing
@testable import PortHarborCore

@Test func exposureClassificationExplainsCommonBindAddresses() {
    #expect(NetworkExposure.classify(address: "127.0.0.1") == .onlyThisMac)
    #expect(NetworkExposure.classify(address: "::1") == .onlyThisMac)
    #expect(NetworkExposure.classify(address: "0.0.0.0") == .allInterfaces)
    #expect(NetworkExposure.classify(address: "::") == .allInterfaces)
    #expect(NetworkExposure.classify(address: "192.168.1.12") == .localNetwork)
}

@Test func systemServicesCannotBeStopped() {
    let endpoint = ListenerEndpoint(address: "127.0.0.1", port: 631, family: .ipv4)
    let process = ProcessIdentity(
        pid: 100,
        parentPID: 1,
        processGroupID: 100,
        name: "system-service"
    )
    let service = DiscoveredService(
        endpoint: endpoint,
        process: process,
        category: .system
    )

    #expect(service.canStop == false)
}

@Test func projectConfidenceIsClamped() {
    let project = ProjectMatch(
        name: "Example",
        rootPath: "/tmp/example",
        confidence: 1.5,
        evidence: []
    )

    #expect(project.confidence == 1)
}
