import Foundation
import PortHarborCore

public struct ProcessTable: Sendable {
    public let processesByPID: [Int32: ProcessIdentity]

    public init(processes: [ProcessIdentity]) {
        self.processesByPID = Dictionary(
            processes.map { ($0.pid, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    public subscript(pid: Int32) -> ProcessIdentity? {
        processesByPID[pid]
    }

    public func ancestry(
        for pid: Int32,
        maximumDepth: Int = 64
    ) -> [ProcessIdentity] {
        guard maximumDepth > 0 else { return [] }

        var result: [ProcessIdentity] = []
        var visited = Set<Int32>([pid])
        var currentPID = processesByPID[pid]?.parentPID

        while
            let candidatePID = currentPID,
            candidatePID > 0,
            result.count < maximumDepth,
            visited.insert(candidatePID).inserted,
            let process = processesByPID[candidatePID]
        {
            result.append(process)
            currentPID = process.parentPID
        }

        return result
    }
}

public struct PSProcessParser: Sendable {
    private static let locale = Locale(identifier: "en_US_POSIX")

    public init() {}

    public func parse(_ output: String) -> ProcessTable {
        ProcessTable(processes: output.split(whereSeparator: \Character.isNewline).compactMap(parseLine))
    }

    private func parseLine(_ line: Substring) -> ProcessIdentity? {
        let fields = line.split(
            maxSplits: 8,
            omittingEmptySubsequences: true,
            whereSeparator: \Character.isWhitespace
        )

        guard
            fields.count == 9,
            let pid = Int32(fields[0]),
            let parentPID = Int32(fields[1]),
            let processGroupID = Int32(fields[2])
        else {
            return nil
        }

        let startTimeText = fields[3...7].joined(separator: " ")
        let executablePath = String(fields[8])

        return ProcessIdentity(
            pid: pid,
            parentPID: parentPID,
            processGroupID: processGroupID,
            name: URL(fileURLWithPath: executablePath).lastPathComponent,
            executablePath: executablePath,
            startTime: Self.startTimeFormatter.date(from: startTimeText)
        )
    }

    private static let startTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return formatter
    }()
}
