import Foundation
import Network
import PortHarborCore

public protocol ServiceHealthChecking: Sendable {
    func check(service: DiscoveredService) async -> ServiceHealth
}

public protocol SnapshotHealthEnriching: Sendable {
    func enrich(_ snapshot: ServiceSnapshot) async -> ServiceSnapshot
}

public struct ProtocolAwareHealthChecker: ServiceHealthChecking {
    private let timeout: Duration

    public init(timeout: Duration = .milliseconds(750)) {
        self.timeout = timeout
    }

    public func check(service: DiscoveredService) async -> ServiceHealth {
        let endpoint = service.endpoint

        if isLikelyWebService(service) {
            let headResult = await checkHTTP(endpoint: endpoint, method: "HEAD")
            switch headResult {
            case .responding:
                return .responding
            case .methodUnsupported:
                return await checkHTTP(endpoint: endpoint, method: "GET").health
            case .timedOut:
                return .unknown
            case .failed:
                break
            }
        }

        return await checkTCP(endpoint: endpoint)
    }

    private func isLikelyWebService(_ service: DiscoveredService) -> Bool {
        let commonWebPorts: Set<UInt16> = [
            80, 443, 3000, 3001, 4000, 5000, 5173, 7000, 8000, 8080, 8081, 8888
        ]
        let webProcessNames: Set<String> = [
            "node", "bun", "deno", "python", "python3", "ruby", "php", "java"
        ]

        return commonWebPorts.contains(service.endpoint.port)
            || (service.project != nil && webProcessNames.contains(service.process.name.lowercased()))
    }

    private func checkHTTP(
        endpoint: ListenerEndpoint,
        method: String
    ) async -> HTTPProbeResult {
        guard let url = localURL(for: endpoint) else { return .failed }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout.timeInterval
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("PortHarbor/1", forHTTPHeaderField: "User-Agent")
        if method == "GET" {
            request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else { return .failed }

            if method == "HEAD" && [405, 501].contains(response.statusCode) {
                return .methodUnsupported
            }

            return (100...599).contains(response.statusCode) ? .responding : .failed
        } catch let error as URLError where error.code == .timedOut {
            return .timedOut
        } catch {
            return .failed
        }
    }

    private func checkTCP(endpoint: ListenerEndpoint) async -> ServiceHealth {
        guard let port = NWEndpoint.Port(rawValue: endpoint.port) else {
            return .unknown
        }

        let host = NWEndpoint.Host(localHost(for: endpoint))
        let connection = NWConnection(host: host, port: port, using: .tcp)

        return await withTaskGroup(of: ServiceHealth.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    let state = HealthContinuationState(continuation: continuation)
                    connection.stateUpdateHandler = { update in
                        switch update {
                        case .ready:
                            state.resume(with: .responding)
                            connection.cancel()
                        case .failed:
                            state.resume(with: .unreachable)
                            connection.cancel()
                        case .cancelled:
                            state.resume(with: .unknown)
                        default:
                            break
                        }
                    }
                    connection.start(queue: .global(qos: .utility))
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return .unknown
            }

            let result = await group.next() ?? .unknown
            connection.cancel()
            group.cancelAll()
            return result
        }
    }

    private func localURL(for endpoint: ListenerEndpoint) -> URL? {
        let host = localHost(for: endpoint)
        let formattedHost = host.contains(":") ? "[\(host)]" : host
        return URL(string: "http://\(formattedHost):\(endpoint.port)/")
    }

    private func localHost(for endpoint: ListenerEndpoint) -> String {
        let normalized = endpoint.address
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))

        if normalized == "*" || normalized == "0.0.0.0" {
            return "127.0.0.1"
        }
        if normalized == "::" {
            return "::1"
        }
        return normalized
    }
}

private enum HTTPProbeResult {
    case responding
    case methodUnsupported
    case timedOut
    case failed

    var health: ServiceHealth {
        switch self {
        case .responding:
            return .responding
        case .timedOut:
            return .unknown
        case .methodUnsupported, .failed:
            return .unreachable
        }
    }
}

private final class HealthContinuationState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ServiceHealth, Never>?

    init(continuation: CheckedContinuation<ServiceHealth, Never>) {
        self.continuation = continuation
    }

    func resume(with health: ServiceHealth) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: health)
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

public actor HealthEnricher<Checker: ServiceHealthChecking>: SnapshotHealthEnriching {
    private struct CacheEntry: Sendable {
        let health: ServiceHealth
        let expiresAt: ContinuousClock.Instant
    }

    private let checker: Checker
    private let cacheDuration: Duration
    private let maximumConcurrency: Int
    private let clock = ContinuousClock()
    private var cache: [String: CacheEntry] = [:]

    public init(
        checker: Checker,
        cacheDuration: Duration = .seconds(3),
        maximumConcurrency: Int = 6
    ) {
        self.checker = checker
        self.cacheDuration = cacheDuration
        self.maximumConcurrency = max(1, maximumConcurrency)
    }

    public func enrich(_ snapshot: ServiceSnapshot) async -> ServiceSnapshot {
        let now = clock.now
        cache = cache.filter { $0.value.expiresAt > now }

        var results: [String: ServiceHealth] = [:]
        var pending: [DiscoveredService] = []

        for service in snapshot.services {
            if let cached = cache[service.id], cached.expiresAt > now {
                results[service.id] = cached.health
            } else {
                pending.append(service)
            }
        }

        for batchStart in stride(from: 0, to: pending.count, by: maximumConcurrency) {
            let batchEnd = min(batchStart + maximumConcurrency, pending.count)
            let batch = Array(pending[batchStart..<batchEnd])

            await withTaskGroup(of: (String, ServiceHealth).self) { group in
                for service in batch {
                    group.addTask { [checker] in
                        (service.id, await checker.check(service: service))
                    }
                }

                for await (serviceID, health) in group {
                    results[serviceID] = health
                    cache[serviceID] = CacheEntry(
                        health: health,
                        expiresAt: clock.now.advanced(by: cacheDuration)
                    )
                }
            }
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
                    health: results[service.id] ?? .unknown
                )
            },
            isStale: snapshot.isStale,
            diagnostic: snapshot.diagnostic
        )
    }
}
