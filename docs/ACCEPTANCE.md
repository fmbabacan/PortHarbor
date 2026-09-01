# PortHarbor v1 Acceptance Criteria

PortHarbor v1 is complete only when all criteria below are satisfied.

1. On a clean macOS 15+ user account, it discovers real TCP listeners without permission prompts, accounts, or configuration.
2. It associates IPv4 and IPv6 listeners with the correct port, bind address, and process.
3. It classifies services into Development, Background Services, and System, with termination disabled for System.
4. It associates supported development projects with a confidence score and visible evidence.
5. It reports exposure and protocol-aware health without misleading certainty.
6. The main window, inspector, timeline, and menu bar consume the same snapshot source.
7. Safety tests prove that target resolution never crosses shells, terminal applications, editors, Docker, launchd, service managers, system processes, or PortHarbor's ancestry.
8. It prevents signalling a stale or reused PID.
9. It never sends SIGKILL without a separate explicit user action.
10. Activity stores meaningful events only, excludes sensitive data, supports 24-hour, 7-day, and 30-day retention policies, and preserves backward-compatible persistence.
11. The English interface is keyboard accessible and readable in light and dark appearances, with all strings in a String Catalog.
12. Unit, integration, runtime smoke, and UI smoke test suites pass.
13. Performance and energy measurements meet the documented budgets, or an accepted exception is documented before release.
14. Apple Silicon and Intel archives are Developer ID signed, notarized, stapled, and pass Gatekeeper verification.
15. GitHub Release assets, checksums, Sparkle appcast, and Homebrew Cask reference the same verified version and artifacts.
16. A testable intermediate build is installed on the development Mac for real-service evaluation.
17. The public repository contains launch-ready README, screenshots, demo, license, architecture, security, contribution, and publishing documentation.
18. Logical port identity, endpoint identity, and service-instance identity remain distinct and are covered by migration and query tests.
19. Watchlist notifications are opt-in, local-only, and limited to meaningful changes for watched ports.
20. Diagnostic exports omit project paths, executable paths, command arguments, and environment data.
