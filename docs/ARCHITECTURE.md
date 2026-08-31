# PortHarbor Architecture

## Structure

PortHarbor is a modular Swift Package distributed as one native macOS application bundle.

- PortHarborCore: immutable models, classifications, and shared protocols.
- PortHarborDiscovery: listener, process, project, exposure, and health discovery.
- PortHarborSafety: pure target resolution, identity validation, and termination policy.
- PortHarborTimeline: snapshot diffing, event coalescing, persistence, clearing, and 24-hour retention.
- PortHarborApp: SwiftUI main window, inspector, timeline, menu bar, onboarding guide, and settings.

## Data flow

System Snapshot -> Discovery -> Process and Project Enrichment -> Classification -> Health -> Safety Analysis -> Timeline Diff -> Immutable UI Snapshot

The service engine operates behind actor boundaries. Views never initiate independent scans. The main window and menu bar observe the same immutable snapshot stream.

## Safety boundary

Termination planning is pure logic over a captured process table and is tested independently from signal delivery. Signal delivery requires a fresh process-table capture and successful identity validation. A mismatch cancels the operation and triggers rediscovery.

System services cannot produce executable termination plans. SIGKILL is a distinct user-authorized operation and cannot be reached through automatic escalation.

## Privacy boundary

PortHarbor uses only information available to the current user through macOS APIs and bounded system tools. It requests no privileged helper, administrator password, Accessibility permission, Full Disk Access, account, telemetry consent, or cloud connection.

Timeline persistence stores sanitized service identities and meaningful state transitions only.
