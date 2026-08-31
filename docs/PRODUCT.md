# PortHarbor v1 Product Specification

## Product promise

**Meet every service running on your Mac.**

PortHarbor is a lightweight, zero-configuration, native macOS service radar. It discovers listening TCP services, explains the processes and projects behind them, clarifies network exposure, records meaningful changes for 24 hours, and enables carefully verified intervention.

## Principles

- Native, fast, compact, and immediately useful.
- Local-first, without accounts, telemetry, cloud storage, administrator access, Accessibility, or Full Disk Access.
- Explain uncertainty instead of presenting guesses as facts.
- Refuse unsafe process actions when identity or ancestry cannot be verified.
- Use one immutable snapshot source for the main window, inspector, timeline, and menu bar.

## Supported platform

- macOS 15 or later.
- Separate Apple Silicon and Intel release archives.
- English UI in v1, with every user-facing string managed through a String Catalog.

## User experience

PortHarbor starts discovery immediately and teaches the product through a short guide layered over real results. The main window contains:

1. A quiet radar summary showing active services, network exposure, and recent changes.
2. A dense service list grouped into Development, Background Services, and System.
3. A right-side inspector preserving list context.
4. A change-focused 24-hour timeline.

The inspector presents service identity, port, health, exposure, project evidence, process ancestry, related timeline events, and available actions.

The menu bar presents development services, ports, and health, with search, Open in Browser, Show in Finder, and Safe Stop. It consumes the same engine snapshot as the main window.

## Discovery

- Discover IPv4 and IPv6 TCP listeners.
- Associate listeners with PID, process identity, parent ancestry, and process group.
- Resolve an accessible working directory and nearest Git or project root.
- Recognize common development environments including Node.js, Next.js, Vite, Python, Swift, and Rust.
- Produce confidence-scored project matches from working directory, command, ancestry, and project markers.
- Show the evidence behind every inferred project match.
- Classify services as Development, Background Services, or System.
- Explain exposure as Only This Mac, Local Network, or All Interfaces.

## Health

- Use a short-timeout HEAD request for likely web services and a controlled GET request when needed.
- Use TCP connection checks for databases and unknown protocols.
- Report Responding, Starting, Unreachable, or Unknown.
- Bound health-check concurrency and cache results briefly.
- Never let an unavailable health result block listener discovery.

## Safe stop

- Resolve the target using process groups and parent ancestry.
- Never cross shells, terminal applications, editors, Docker, launchd, service managers, system processes, or PortHarbor's own ancestry.
- Disable stop actions for System services.
- Preview the exact process or job that will receive a signal.
- Immediately before acting, revalidate process start time, ancestry, and process group.
- Reject stale, reused, changed, or uncertain process identities.
- Send SIGTERM first.
- Never send SIGKILL automatically. It requires a separate explicit user action.
- Report success only after verifying that the target exited.

## Timeline

Record only meaningful changes:

- Service started or stopped.
- Port ownership changed.
- Health changed.
- Exposure widened or narrowed.
- Project association changed materially.

Coalesce repeated events, delete records after 24 hours, and allow immediate user clearing. Never persist environment values, file contents, or sensitive command arguments.

## Failure behavior

- Mark a failed scan as stale rather than presenting old results as current.
- Isolate per-process failures from the overall scan.
- Show inaccessible fields as Unavailable.
- Do not interpret a health timeout as proof that a service is stopped.
- Continue live discovery if timeline persistence fails.
- Refuse termination when safety validation is inconclusive.
- Present understandable errors, retry actions, and optional technical details.

## Performance targets

- First real snapshot within two seconds of cold launch on a typical developer Mac.
- Approximately two-second adaptive polling while the main window is visible.
- Less frequent polling while resident only in the menu bar.
- Average idle CPU below 1 percent under normal conditions.
- Typical memory use below 80 MB.
- No discovery, enrichment, or health work blocking the main thread.
- Bounded timeline storage and a compact native application bundle.

## Out of scope for v1

- Saving project launch commands or starting services.
- Live log terminals and workspace orchestration.
- MCP integration and Docker management.
- Port reservation and QR sharing.
- UDP and Unix socket discovery.

## License

Apache License 2.0.
