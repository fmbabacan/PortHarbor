import Foundation
import PortHarborCore

public struct WorkingDirectoryParser: Sendable {
    public init() {}

    public func parse(_ output: String) -> [Int32: String] {
        var currentPID: Int32?
        var directories: [Int32: String] = [:]

        for line in output.split(whereSeparator: \Character.isNewline) {
            guard let field = line.first else { continue }
            let value = String(line.dropFirst())

            switch field {
            case "p":
                currentPID = Int32(value)
            case "n":
                guard let pid = currentPID, value.hasPrefix("/") else { continue }
                directories[pid] = value
            default:
                continue
            }
        }

        return directories
    }
}

public protocol ProjectFileInspecting: Sendable {
    func itemExists(at path: String) -> Bool
}

public struct LocalProjectFileInspector: ProjectFileInspecting {
    public init() {}

    public func itemExists(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}

public struct ProjectResolver<Inspector: ProjectFileInspecting>: Sendable {
    private let inspector: Inspector
    private let markerWeights: [String: Double] = [
        ".git": 0.35,
        "package.json": 0.30,
        "Package.swift": 0.30,
        "Cargo.toml": 0.30,
        "pyproject.toml": 0.30,
        "requirements.txt": 0.20,
        "vite.config.js": 0.15,
        "vite.config.ts": 0.15,
        "next.config.js": 0.15,
        "next.config.mjs": 0.15,
        "next.config.ts": 0.15
    ]

    public init(inspector: Inspector) {
        self.inspector = inspector
    }

    public func resolve(
        workingDirectory: String?,
        process: ProcessIdentity,
        ancestry: [ProcessIdentity]
    ) -> ProjectMatch? {
        guard
            let workingDirectory,
            workingDirectory != "/",
            !workingDirectory.hasPrefix("/System/"),
            !workingDirectory.hasPrefix("/Applications/")
        else {
            return nil
        }

        guard let root = nearestProjectRoot(from: workingDirectory) else {
            return nil
        }

        var evidence = [
            ProjectEvidence(
                kind: .workingDirectory,
                summary: "Process working directory is inside \(root)",
                weight: 0.40
            )
        ]

        for marker in markerWeights.keys.sorted() {
            guard inspector.itemExists(at: root + "/" + marker) else { continue }
            evidence.append(
                ProjectEvidence(
                    kind: .projectMarker,
                    summary: "Found \(marker)",
                    weight: markerWeights[marker] ?? 0
                )
            )
        }

        let developmentNames = Set([
            "node", "bun", "deno", "python", "python3", "swift", "cargo", "rustc"
        ])
        let relevantProcess = ([process] + ancestry).first {
            developmentNames.contains($0.name.lowercased())
        }

        if let relevantProcess {
            evidence.append(
                ProjectEvidence(
                    kind: relevantProcess.pid == process.pid ? .command : .ancestry,
                    summary: "Development process \(relevantProcess.name) is associated with the listener",
                    weight: 0.15
                )
            )
        }

        let confidence = min(evidence.reduce(0) { $0 + $1.weight }, 1)
        guard confidence >= 0.50 else { return nil }

        return ProjectMatch(
            name: URL(fileURLWithPath: root).lastPathComponent,
            rootPath: root,
            confidence: confidence,
            evidence: evidence
        )
    }

    private func nearestProjectRoot(from directory: String) -> String? {
        var candidate = URL(fileURLWithPath: directory).standardizedFileURL
        let rootPath = URL(fileURLWithPath: "/").path

        while candidate.path != rootPath {
            if markerWeights.keys.contains(where: {
                inspector.itemExists(at: candidate.path + "/" + $0)
            }) {
                return candidate.path
            }
            candidate.deleteLastPathComponent()
        }

        return nil
    }
}

public extension ProjectResolver where Inspector == LocalProjectFileInspector {
    init() {
        self.init(inspector: LocalProjectFileInspector())
    }
}
