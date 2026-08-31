# PortHarbor

Meet every service running on your Mac.

PortHarbor is a lightweight native macOS service radar. It discovers local TCP listeners, connects them to processes and development projects, explains network exposure and health, records meaningful changes for 24 hours, and provides a carefully verified Safe Stop workflow.

## Demo

See [the v1 demo walkthrough](docs/DEMO.md) for the end-to-end discovery, inspection, timeline, menu bar, and Safe Stop flow.

## Requirements

- macOS 15 or later
- Apple Silicon or Intel Mac
- No account, administrator access, Accessibility permission, or Full Disk Access

## Install

Download the archive for your Mac from GitHub Releases, extract it, and move PortHarbor.app to Applications. Homebrew Cask installation will also be available:

    brew install --cask fmbabacan/tap/portharbor

## Highlights

- Zero-configuration IPv4 and IPv6 TCP listener discovery
- Process, ancestry, project, confidence, exposure, and protocol-aware health enrichment
- One actor-isolated snapshot stream shared by the main window and menu bar
- Privacy-preserving 24-hour change timeline
- Job-aware Safe Stop using fresh identity validation, SIGTERM first, and separately confirmed SIGKILL
- Native SwiftUI interface for macOS 15+

## Build and test

    swift test
    swift build -c release
    ./scripts/package-local-app.sh

The local packaging script creates an ad-hoc signed development build and installs it in the current user's Applications directory. Public releases use Developer ID signing and Apple notarization.

## Documentation

- Product specification: docs/PRODUCT.md
- Architecture: docs/ARCHITECTURE.md
- Acceptance criteria: docs/ACCEPTANCE.md
- Publishing guide: docs/PUBLISHING.md
- Performance record: docs/PERFORMANCE.md
- Demo walkthrough: docs/DEMO.md

## Privacy

PortHarbor runs locally and has no telemetry, account, analytics, or cloud service. Timeline records contain sanitized display information only.

## License

Licensed under the Apache License 2.0. See LICENSE and NOTICE.
