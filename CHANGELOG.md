# Changelog

All notable changes to PortHarbor are documented here. The format follows Keep a Changelog, and releases use Semantic Versioning.

## [Unreleased]

## [1.0.2] - 2026-09-01

### Fixed

- Fixed the initial Services layout so the service list fills the available window height and starts at the top before a service is selected.

## [1.0.1] - 2026-09-01

### Added

- Added Sparkle 2.9.6 automatic update checks and a manual Check for Updates command.
- Embedded and validated the Sparkle updater, autoupdate executable, and XPC services in packaged applications.
- Added explicit release-secret validation before signing and notarization.

### Changed

- Improved the initial service-list layout so every category uses the full window height before a service is selected.

## [1.0.0] - 2026-08-31

### Added

- Native macOS service discovery and inspection.
- IPv4 and IPv6 TCP listener enrichment.
- Process identity, ancestry, process-group, and project resolution.
- Confidence-scored project evidence and network exposure classification.
- Protocol-aware HTTP and TCP health checks.
- One actor-isolated snapshot stream shared by the main window and menu bar.
- Privacy-preserving 24-hour change timeline.
- Job-aware Safe Stop with fresh identity validation, SIGTERM first, and separately confirmed SIGKILL.
- Developer ID signed and Apple-notarized Apple Silicon and Intel builds.
- Sparkle update metadata and Homebrew Cask distribution.

[Unreleased]: https://github.com/fmbabacan/PortHarbor/compare/v1.0.2...HEAD
[1.0.2]: https://github.com/fmbabacan/PortHarbor/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/fmbabacan/PortHarbor/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/fmbabacan/PortHarbor/releases/tag/v1.0.0
