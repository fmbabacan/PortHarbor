import Foundation
import PortHarborCore

public actor DiscoveryEngine {
    private let provider: any ServiceDiscovering
    private let healthEnricher: (any SnapshotHealthEnriching)?
    private var latestSnapshot: ServiceSnapshot = .empty
    private var subscribers: [UUID: AsyncStream<ServiceSnapshot>.Continuation] = [:]

    public init(
        provider: any ServiceDiscovering,
        healthEnricher: (any SnapshotHealthEnriching)? = nil
    ) {
        self.provider = provider
        self.healthEnricher = healthEnricher
    }

    public func scan() async -> ServiceSnapshot {
        do {
            let snapshot = try await provider.discover()
            publish(snapshot)

            guard let healthEnricher else {
                return snapshot
            }

            let enrichedSnapshot = await healthEnricher.enrich(snapshot)

            guard latestSnapshot.capturedAt == snapshot.capturedAt else {
                return latestSnapshot
            }

            publish(enrichedSnapshot)
            return enrichedSnapshot
        } catch {
            let staleSnapshot = ServiceSnapshot(
                capturedAt: latestSnapshot.capturedAt,
                services: latestSnapshot.services,
                isStale: true,
                diagnostic: String(describing: error)
            )
            publish(staleSnapshot)
            return staleSnapshot
        }
    }

    public func currentSnapshot() -> ServiceSnapshot {
        latestSnapshot
    }

    public func snapshots() -> AsyncStream<ServiceSnapshot> {
        let subscriberID = UUID()
        let initialSnapshot = latestSnapshot

        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            subscribers[subscriberID] = continuation
            continuation.yield(initialSnapshot)
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeSubscriber(subscriberID)
                }
            }
        }
    }

    public func discoverWithoutWaitingForHealth() async -> ServiceSnapshot {
        do {
            let snapshot = try await provider.discover()
            publish(snapshot)
            return snapshot
        } catch {
            let staleSnapshot = ServiceSnapshot(
                capturedAt: latestSnapshot.capturedAt,
                services: latestSnapshot.services,
                isStale: true,
                diagnostic: String(describing: error)
            )
            publish(staleSnapshot)
            return staleSnapshot
        }
    }

    public func refreshHealth() async -> ServiceSnapshot {
        guard let healthEnricher else {
            return latestSnapshot
        }

        let sourceSnapshot = latestSnapshot
        let enrichedSnapshot = await healthEnricher.enrich(sourceSnapshot)

        guard latestSnapshot.capturedAt == sourceSnapshot.capturedAt else {
            return latestSnapshot
        }

        publish(enrichedSnapshot)
        return enrichedSnapshot
    }

    private func publish(_ snapshot: ServiceSnapshot) {
        latestSnapshot = snapshot
        for continuation in subscribers.values {
            continuation.yield(snapshot)
        }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
    }
}
