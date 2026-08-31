# Contributing

Thank you for helping improve PortHarbor.

1. Open an issue describing the proposed change.
2. Keep changes within the module boundaries documented in docs/ARCHITECTURE.md.
3. Add or update tests for behavior changes.
4. Run swift test, swift build -c release, and git diff --check.
5. Submit a focused pull request explaining user-visible and safety implications.

Safe Stop changes require tests proving fresh identity validation, protected ancestry behavior, and explicit authorization boundaries.
