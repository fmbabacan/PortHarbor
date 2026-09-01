# Changelog

All notable changes to PortHarbor are documented here. The format follows Keep a Changelog, and releases use Semantic Versioning.

## [Unreleased]

## [1.1.0] - 2026-09-01

### Added

- Added logical TCP port history that remains continuous across bind-address, IP-family, PID, and process-instance changes.
- Added structured, privacy-safe Activity event context with backward-compatible timeline persistence and port-based queries.
- Added lifecycle details including first seen, running time, restart count, recent activity, and a 24-hour health and availability strip.
- Added a filterable global Activity center with port, event-type, process, project, and free-text filtering.
- Added Services summary controls and smart filters for development, unhealthy, exposed, unknown-project, and stoppable services.
- Added persistent port favorites, a local watchlist, optional local notifications, and a focused menu-bar view.
- Added project-match evidence, occupied-port diagnosis, and privacy-safe text and JSON diagnostic summaries.

### Changed

- Renamed Timeline to Activity throughout the primary navigation and settings experience.
- Reworked the service inspector for narrow widths with compact icon-labelled actions and direct full-history navigation.
- Improved empty-selection list alignment, light and dark appearance behavior, and accessibility labels for status and history controls.

### Fixed

- Preserved one logical port history when endpoint ownership or listener identity changes.
- Prevented diagnostic summaries from including project paths, executable paths, command arguments, or environment data.

## [1.0.4] - 2026-09-01

### Fixed

- Removed the packaged application's runtime dependency on Swift Package Manager's development-only `Bundle.module` fallback, preventing a main-thread `SIGTRAP` when localized service category titles are rendered.
- Isolated the packaged-application startup test from the Swift build directory so missing application resources can no longer be masked by development-build fallback paths.

## [1.0.3] - 2026-09-01

### Fixed

- Fixed packaged applications closing immediately at launch because the embedded Sparkle framework could not be resolved from the application bundle.
- Added a packaged-application startup smoke test to CI to prevent invalid framework search paths from reaching future releases.

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

[Unreleased]: https://github.com/fmbabacan/PortHarbor/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/fmbabacan/PortHarbor/compare/v1.0.4...v1.1.0
[1.0.4]: https://github.com/fmbabacan/PortHarbor/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/fmbabacan/PortHarbor/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/fmbabacan/PortHarbor/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/fmbabacan/PortHarbor/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/fmbabacan/PortHarbor/releases/tag/v1.0.0
