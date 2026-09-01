# Publishing PortHarbor

## Required credentials

- Developer ID Application certificate
- Apple notarization credentials
- GitHub repository release permission
- Sparkle signing key when automatic updates are enabled

## Release sequence

1. Update VERSION and CHANGELOG.md.
2. Run unit, integration, live runtime, and UI smoke tests on macOS 15.
3. Produce separate Apple Silicon and Intel application archives.
4. Sign each application with Developer ID and the hardened runtime.
5. Submit each archive for notarization, staple the ticket, and verify it with Gatekeeper.
6. Generate SHA-256 checksums and Sparkle EdDSA signatures.
7. Publish the matching GitHub Release assets.
8. Update appcast.xml and the Homebrew Cask with the exact version, URLs, signatures, and checksums.
9. Download the published assets and independently verify SHA-256 values, bundle version, architecture, RPATH, Developer ID signature, notarization ticket, Gatekeeper acceptance, and isolated startup behavior.

Never publish an ad-hoc signed local package. Public artifacts must be Developer ID signed, notarized, stapled, and accepted by Gatekeeper.

## Automation

- The CI workflow runs unit and integration tests, validates the String Catalog, builds the release configuration, exercises live listener discovery, and checks packaging and distribution scripts.
- The release workflow creates separate Apple Silicon and Intel archives, imports the Developer ID certificate, signs with hardened runtime, submits for notarization, staples the ticket, and uploads the resulting archives and checksums.
- Run scripts/ui-smoke.sh to launch the packaged application and verify that PortHarbor owns a visible on-screen window without Accessibility permission.
- Run scripts/performance-smoke.sh for the reproducible cold-build and live-discovery smoke budget. Record idle CPU, memory, and energy measurements on representative hardware before publishing v1.
- The measured v1 results and accepted memory exception are recorded in docs/PERFORMANCE.md.
- Run scripts/generate-distribution-metadata.sh after both verified archives and their Sparkle EdDSA signatures are available. It generates appcast.xml and Casks/portharbor.rb from those exact artifacts.
