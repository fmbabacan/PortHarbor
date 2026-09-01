import Foundation
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
@Test func serviceExposesDistinctPortEndpointAndInstanceIdentities() {
    let endpoint = ListenerEndpoint(address: "127.0.0.1", port: 3000, family: .ipv4)
    let service = DiscoveredService(
        endpoint: endpoint,
        process: ProcessIdentity(
            pid: 42, parentPID: 1, processGroupID: 42, name: "node",
            startTime: Date(timeIntervalSince1970: 100)
        ),
        category: .development
    )
    #expect(service.portID == "tcp:3000")
    #expect(service.endpointID == "tcp:ipv4:127.0.0.1:3000")
    #expect(service.serviceInstanceID == "42:100.0")
}
