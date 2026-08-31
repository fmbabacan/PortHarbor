<div align="center">

# PortHarbor

**Meet every service running on your Mac.**

A native, local-first service radar for discovering TCP listeners, understanding the processes behind them, and stopping development services safely.

[![Release](https://img.shields.io/github/v/release/fmbabacan/PortHarbor?style=flat-square&color=2ea44f)](https://github.com/fmbabacan/PortHarbor/releases/latest)
[![CI](https://img.shields.io/github/actions/workflow/status/fmbabacan/PortHarbor/ci.yml?branch=main&style=flat-square&label=CI)](https://github.com/fmbabacan/PortHarbor/actions/workflows/ci.yml)
[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-000000?style=flat-square&logo=apple)](https://support.apple.com/macos)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white)](https://www.swift.org/)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue?style=flat-square)](LICENSE)

[Install](#install) · [Features](#features) · [How it works](#how-it-works) · [Safety](#safe-stop-by-design) · [Documentation](#documentation)

</div>

PortHarbor turns an anonymous list of open ports into an understandable map of local software. It connects every discovered listener to process identity, ancestry, project evidence, network exposure, and health while keeping all operations on the Mac.

## Why PortHarbor

Development environments quietly accumulate web servers, language runtimes, container helpers, design tools, and background agents. Finding the process behind a port usually means switching between multiple command-line tools and manually interpreting their output. PortHarbor brings that context into one native interface.

## Features

- **Zero-configuration discovery.** Find IPv4 and IPv6 TCP listeners without setup, an account, administrator access, or additional permissions.
- **Process context.** Inspect ports, bind addresses, process identities, process groups, and ancestry.
- **Project resolution.** Connect supported development services to project roots with visible confidence evidence.
- **Exposure awareness.** Distinguish services available only on this Mac from listeners reachable on the local network or all interfaces.
- **Protocol-aware health.** Use bounded HTTP and TCP checks without delaying listener discovery.
- **Private timeline.** Review meaningful starts, stops, health changes, exposure changes, and port ownership changes for 24 hours.
- **Safe Stop.** Stop eligible development services only after fresh identity and ancestry validation.
- **Shared state.** Keep the main window and menu bar synchronized through one actor-isolated snapshot stream.

## Install

### Homebrew

```sh
brew install --cask fmbabacan/tap/portharbor
```

### Direct download

Download the Apple Silicon or Intel archive from the [latest release](https://github.com/fmbabacan/PortHarbor/releases/latest), extract it, and move `PortHarbor.app` to Applications.

Public builds are Developer ID signed, notarized by Apple, stapled, and published with SHA-256 checksums.

### Requirements

- macOS 15 Sequoia or later
- Apple Silicon or Intel Mac
- No account, administrator access, Accessibility permission, or Full Disk Access

## How it works

```text
TCP listeners
      |
      v
Process identity and ancestry ---> Project evidence
      |                                  |
      +----------------+-----------------+
                       v
         Classification, exposure, health
                       |
                       v
          One immutable snapshot stream
                +------+------ +
                v               v
           Main window       Menu bar
                |
                v
         Privacy-safe timeline
```

The discovery engine is actor-isolated. The main window and menu bar observe the same immutable snapshot stream, so independent views cannot disagree about current state. See the [architecture guide](docs/ARCHITECTURE.md) for module boundaries and data flow.

## Safe Stop by design

Stopping the wrong process is worse than leaving a stale service running. PortHarbor therefore treats termination as a safety-critical operation.

1. The selected service is evaluated against system and protected-ancestry rules.
2. PortHarbor determines whether one process or an isolated job group is eligible.
3. Process start time, ancestry, and process group are captured again immediately before delivery.
4. Any stale, reused, changed, or uncertain identity cancels the operation.
5. `SIGTERM` is delivered first and success is reported only after exit is verified.
6. `SIGKILL` is never automatic and requires a second explicit confirmation.

System services cannot be stopped through PortHarbor. Safety policy, target planning, identity validation, and signal delivery are separated and tested independently.

## Privacy

PortHarbor is local-first by construction:

- no telemetry, analytics, advertising, account, or cloud service
- no privileged helper or administrator password
- no Accessibility or Full Disk Access requirement
- no stored environment values, file contents, or sensitive command arguments
- timeline data expires after 24 hours and can be cleared immediately

See [SECURITY.md](SECURITY.md) for vulnerability reporting and security support.

## Build from source

Xcode Command Line Tools with Swift 6 are required.

```sh
git clone https://github.com/fmbabacan/PortHarbor.git
cd PortHarbor
swift test
swift build -c release
./scripts/package-local-app.sh
```

The packaging script creates an ad-hoc signed development build for local testing. It must not be redistributed as a public release. The Developer ID and notarization process is documented in [docs/PUBLISHING.md](docs/PUBLISHING.md).

## Documentation

| Guide | Purpose |
| --- | --- |
| [Documentation index](docs/README.md) | Product, engineering, validation, and release references |
| [Product specification](docs/PRODUCT.md) | Product promise, behavior, scope, and performance targets |
| [Architecture](docs/ARCHITECTURE.md) | Modules, concurrency, privacy, and safety boundaries |
| [Demo walkthrough](docs/DEMO.md) | End-to-end product tour |
| [Performance record](docs/PERFORMANCE.md) | Measured v1 performance and accepted exception |
| [Publishing](docs/PUBLISHING.md) | Signing, notarization, Sparkle, and distribution |
| [Acceptance criteria](docs/ACCEPTANCE.md) | Release-readiness checklist used for v1 |

## Project status

PortHarbor 1.0.0 is the first stable release. The current scope covers TCP listeners on macOS 15 and later. UDP, Unix sockets, service launch commands, Docker management, and log terminals are intentionally outside the v1 scope.

See the [changelog](CHANGELOG.md) or browse [open issues](https://github.com/fmbabacan/PortHarbor/issues).

## Contributing

Focused bug reports, accessibility improvements, performance work, documentation updates, and well-scoped feature proposals are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md), [SUPPORT.md](SUPPORT.md), and the [Code of Conduct](CODE_OF_CONDUCT.md) before participating.

## License

PortHarbor is available under the [Apache License 2.0](LICENSE).
