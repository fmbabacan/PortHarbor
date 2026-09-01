import AppKit
import Observation
import PortHarborCore
import PortHarborDiscovery
import PortHarborSafety
import PortHarborTimeline
import Sparkle
import SwiftUI

private func localized(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .main)
}

@main
struct PortHarborApp: App {
    @State private var model = PortHarborModel()
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var body: some Scene {
        WindowGroup("PortHarbor") {
            MainWindow(model: model)
                .task { model.start() }
        }
        .defaultSize(width: 1120, height: 720)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updaterController.checkForUpdates(nil)
                }
                .disabled(!updaterController.updater.canCheckForUpdates)
            }

            CommandGroup(after: .newItem) {
                Button("Refresh Services") { model.refresh() }
                    .keyboardShortcut("r")
            }
        }

        MenuBarExtra("PortHarbor", systemImage: "dot.radiowaves.left.and.right") {
            MenuBarContent(model: model)
                .task { model.start() }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}

@MainActor
@Observable
final class PortHarborModel {
    enum Page: String, CaseIterable, Identifiable {
        case services = "Services"
        case timeline = "Timeline"

        var id: Self { self }
    }

    private let engine: DiscoveryEngine
    private let stopExecutor = SafeStopExecutor(
        inspector: LiveProcessInspector(),
        delivery: DarwinSignalDelivery()
    )
    private let timelineStore: TimelineStore<JSONFileTimelinePersistence>
    private var observationTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?

    var snapshot = ServiceSnapshot.empty
    var timeline: [TimelineEvent] = []
    var selectedServiceID: String?
    var selectedPage: Page = .services
    var searchText = ""
    var isRefreshing = false
    var isStopping = false
    var refreshInterval: TimeInterval = 5
    var stopPrompt: StopPrompt?
    var stopNotice: StopNotice?

    enum StopPrompt: Identifiable {
        case graceful(TerminationPlan, String)
        case force(TerminationPlan, String)

        var id: String {
            switch self {
            case let .graceful(plan, _): "graceful:\(plan.serviceID)"
            case let .force(plan, _): "force:\(plan.serviceID)"
            }
        }

        var title: String {
            switch self {
            case .graceful: localized("Stop this service?")
            case .force: localized("Force stop this service?")
            }
        }

        var actionTitle: String {
            switch self {
            case .graceful: localized("Stop")
            case .force: localized("Force Stop")
            }
        }

        var message: String {
            switch self {
            case let .graceful(plan, name):
                localized("PortHarbor will send SIGTERM to \(name). \(plan.explanation) The process identity will be checked again immediately before the signal is sent.")
            case let .force(plan, name):
                localized("The service did not exit after SIGTERM. PortHarbor will send SIGKILL to \(name) only after revalidating its process identity. \(plan.explanation)")
            }
        }
    }

    struct StopNotice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    init() {
        let persistence: JSONFileTimelinePersistence
        do {
            persistence = try JSONFileTimelinePersistence.applicationSupport()
        } catch {
            persistence = JSONFileTimelinePersistence(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("PortHarbor-timeline.json")
            )
        }
        timelineStore = TimelineStore(persistence: persistence)
        engine = DiscoveryEngine(
            provider: LsofListenerProvider(),
            healthEnricher: HealthEnricher(
                checker: ProtocolAwareHealthChecker()
            )
        )
    }

    func start() {
        guard observationTask == nil else { return }

        Task { [weak self] in
            guard let self else { return }
            await self.timelineStore.restore()
            self.timeline = await self.timelineStore.currentEvents()
        }

        observationTask = Task { [weak self, engine] in
            let stream = await engine.snapshots()
            for await snapshot in stream {
                guard let self, !Task.isCancelled else { return }
                await self.receive(snapshot)
            }
        }

        scanTask = Task { [weak self] in
            guard let self else { return }
            await self.performRefresh()

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self.refreshInterval))
                guard !Task.isCancelled else { return }
                await self.performRefresh()
            }
        }
    }

    func refresh() {
        Task { await performRefresh() }
    }

    func clearTimeline() {
        Task {
            await timelineStore.clear()
            timeline = []
        }
    }

    var filteredServices: [DiscoveredService] {
        guard !searchText.isEmpty else { return snapshot.services }
        let query = searchText.localizedLowercase

        return snapshot.services.filter { service in
            service.process.name.localizedLowercase.contains(query)
                || service.project?.name.localizedLowercase.contains(query) == true
                || String(service.endpoint.port).contains(query)
                || service.endpoint.address.localizedLowercase.contains(query)
        }
    }

    var developmentServices: [DiscoveredService] {
        snapshot.services.filter { $0.category == .development }
    }

    var selectedService: DiscoveredService? {
        guard let selectedServiceID else { return nil }
        return snapshot.services.first { $0.id == selectedServiceID }
    }

    func openInBrowser(_ service: DiscoveredService) {
        let host = localHost(for: service.endpoint)
        let formattedHost = host.contains(":") ? "[\(host)]" : host
        guard let url = URL(
            string: "http://\(formattedHost):\(service.endpoint.port)/"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func showInFinder(_ service: DiscoveredService) {
        guard let path = service.project?.rootPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([
            URL(fileURLWithPath: path)
        ])
    }

    func stopEligibility(for service: DiscoveredService) -> StopEligibility {
        SafetyPolicy().evaluate(service: service)
    }

    func requestSafeStop(_ service: DiscoveredService) {
        do {
            let plan = try TerminationPlanner().plan(
                service: service,
                authorization: .graceful
            )
            stopPrompt = .graceful(plan, displayName(for: service))
        } catch {
            stopNotice = StopNotice(
                title: localized("Service cannot be stopped"),
                message: stopErrorMessage(error)
            )
        }
    }

    func confirmStop(_ prompt: StopPrompt) {
        stopPrompt = nil
        Task { await executeStop(prompt) }
    }

    private func performRefresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        _ = await engine.scan()
        isRefreshing = false
    }

    private func receive(_ snapshot: ServiceSnapshot) async {
        self.snapshot = snapshot
        _ = await timelineStore.ingest(snapshot)
        timeline = await timelineStore.currentEvents()

        if let selectedServiceID,
           !snapshot.services.contains(where: { $0.id == selectedServiceID }) {
            self.selectedServiceID = nil
        }
    }

    private func executeStop(_ prompt: StopPrompt) async {
        guard !isStopping else { return }
        isStopping = true
        defer { isStopping = false }

        let plan: TerminationPlan
        let authorization: StopAuthorization
        let serviceName: String

        switch prompt {
        case let .graceful(value, name):
            plan = value
            authorization = .graceful
            serviceName = name
        case let .force(value, name):
            plan = value
            authorization = .forceKillExplicitlyConfirmed
            serviceName = name
        }

        do {
            try await stopExecutor.execute(plan, authorization: authorization)
            _ = await engine.scan()
            stopNotice = StopNotice(
                title: localized("Service stopped"),
                message: localized("\(serviceName) exited successfully.")
            )
        } catch StopExecutionError.targetDidNotExit where authorization == .graceful {
            guard let service = snapshot.services.first(where: {
                $0.id == plan.serviceID
            }) else {
                stopNotice = StopNotice(
                    title: localized("Service is still running"),
                    message: localized("Refresh discovery before trying again.")
                )
                return
            }

            do {
                let forcePlan = try TerminationPlanner().plan(
                    service: service,
                    authorization: .forceKillExplicitlyConfirmed
                )
                stopPrompt = .force(forcePlan, serviceName)
            } catch {
                stopNotice = StopNotice(
                    title: localized("Force stop unavailable"),
                    message: stopErrorMessage(error)
                )
            }
        } catch {
            _ = await engine.scan()
            stopNotice = StopNotice(
                title: localized("Service was not stopped"),
                message: stopErrorMessage(error)
            )
        }
    }

    private func displayName(for service: DiscoveredService) -> String {
        service.project?.name ?? service.process.name
    }

    private func stopErrorMessage(_ error: Error) -> String {
        switch error {
        case let StopPlanningError.ineligible(reason):
            reason
        case StopExecutionError.processNoLongerExists:
            localized("The process no longer exists. Discovery has been refreshed.")
        case StopExecutionError.identityChanged:
            localized("The process identity changed before the signal could be sent. No action was taken.")
        case StopExecutionError.forceKillRequiresSeparateAuthorization:
            localized("Force Stop requires its own explicit confirmation.")
        case StopExecutionError.targetDidNotExit:
            localized("The process did not exit within the verification period.")
        default:
            String(describing: error)
        }
    }

    private func localHost(for endpoint: ListenerEndpoint) -> String {
        let value = endpoint.address.trimmingCharacters(
            in: CharacterSet(charactersIn: "[]")
        )
        if value == "*" || value == "0.0.0.0" { return "127.0.0.1" }
        if value == "::" { return "::1" }
        return value
    }
}

private struct MainWindow: View {
    @Bindable var model: PortHarborModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedPage) {
                Label("Services", systemImage: "dot.radiowaves.left.and.right")
                    .tag(PortHarborModel.Page.services)
                Label("Timeline", systemImage: "clock.arrow.circlepath")
                    .tag(PortHarborModel.Page.timeline)
            }
            .navigationTitle("PortHarbor")
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            switch model.selectedPage {
            case .services:
                ServicesPage(model: model)
            case .timeline:
                TimelinePage(model: model)
            }
        }
        .frame(minWidth: 820, minHeight: 540)
        .alert(item: $model.stopPrompt) { prompt in
            Alert(
                title: Text(prompt.title),
                message: Text(prompt.message),
                primaryButton: .destructive(Text(prompt.actionTitle)) {
                    model.confirmStop(prompt)
                },
                secondaryButton: .cancel()
            )
        }
        .alert(item: $model.stopNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

private struct ServicesPage: View {
    @Bindable var model: PortHarborModel

    var body: some View {
        GeometryReader { geometry in
            HSplitView {
                serviceList
                    .frame(minWidth: 440)
                    .frame(height: geometry.size.height, alignment: .top)

                ServiceInspector(service: model.selectedService, model: model)
                    .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
                    .frame(height: geometry.size.height)
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: .top
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Services")
        .searchable(
            text: $model.searchText,
            prompt: "Process, project, port, or address"
        )
        .toolbar {
            ToolbarItem {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    model.refresh()
                }
                .disabled(model.isRefreshing)
                .keyboardShortcut("r")
            }
        }
        .overlay(alignment: .bottom) {
            if model.snapshot.isStale {
                Label(
                    "Showing the most recent snapshot because discovery failed.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.callout)
                .padding(10)
                .background(.regularMaterial, in: Capsule())
                .padding()
            }
        }
    }

    @ViewBuilder
    private var serviceList: some View {
        if model.snapshot == .empty && model.isRefreshing {
            ContentUnavailableView(
                "Scanning local services",
                systemImage: "dot.radiowaves.left.and.right",
                description: Text("The first service snapshot is being prepared.")
            )
        } else if model.filteredServices.isEmpty {
            ContentUnavailableView.search(text: model.searchText)
        } else {
            List(selection: $model.selectedServiceID) {
                ForEach(ServiceCategory.allCases, id: \.self) { category in
                    let services = model.filteredServices.filter {
                        $0.category == category
                    }
                    if !services.isEmpty {
                        Section(category.title) {
                            ForEach(services) { service in
                                ServiceRow(service: service)
                                    .tag(service.id)
                                    .contextMenu {
                                        Button("Open in Browser") {
                                            model.openInBrowser(service)
                                        }
                                        Button("Show in Finder") {
                                            model.showInFinder(service)
                                        }
                                        .disabled(service.project == nil)
                                        Divider()
                                        Button("Safe Stop", role: .destructive) {
                                            model.requestSafeStop(service)
                                        }
                                        .disabled(
                                            model.isStopping
                                                || !service.canStop
                                        )
                                    }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct ServiceRow: View {
    let service: DiscoveredService

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: service.category.symbol)
                .frame(width: 24)
                .foregroundStyle(service.health.color)

            VStack(alignment: .leading, spacing: 3) {
                Text(service.project?.name ?? service.process.name)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(service.process.name) · PID \(service.process.pid)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(String(service.endpoint.port))
                    .font(.system(.body, design: .monospaced, weight: .semibold))
                Label(service.health.title, systemImage: service.health.symbol)
                    .font(.caption)
                    .foregroundStyle(service.health.color)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(service.project?.name ?? service.process.name), port \(service.endpoint.port), \(service.health.title)"
        )
    }
}

private struct ServiceInspector: View {
    let service: DiscoveredService?
    let model: PortHarborModel

    var body: some View {
        if let service {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(service.project?.name ?? service.process.name)
                            .font(.title2.bold())
                        Text("Port \(service.endpoint.port)")
                            .font(.title3.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        StatusPill(
                            title: service.health.title,
                            symbol: service.health.symbol,
                            color: service.health.color
                        )
                        StatusPill(
                            title: service.endpoint.exposure.title,
                            symbol: service.endpoint.exposure.symbol,
                            color: service.endpoint.exposure.color
                        )
                    }

                    InspectorSection("Endpoint") {
                        LabeledContent("Address", value: service.endpoint.address)
                        LabeledContent(
                            "Family",
                            value: service.endpoint.family.rawValue.uppercased()
                        )
                    }

                    InspectorSection("Process") {
                        LabeledContent("Name", value: service.process.name)
                        LabeledContent("PID", value: String(service.process.pid))
                        LabeledContent(
                            "Process group",
                            value: String(service.process.processGroupID)
                        )
                    }

                    if let project = service.project {
                        InspectorSection("Project") {
                            LabeledContent("Name", value: project.name)
                            LabeledContent(
                                "Confidence",
                                value: project.confidence.formatted(
                                    .percent.precision(.fractionLength(0))
                                )
                            )
                            Text(project.rootPath)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }

                    if !service.ancestry.isEmpty {
                        InspectorSection("Process ancestry") {
                            ForEach(service.ancestry, id: \.pid) { process in
                                LabeledContent(
                                    process.name,
                                    value: "PID \(process.pid)"
                                )
                            }
                        }
                    }

                    HStack {
                        Button("Open in Browser") {
                            model.openInBrowser(service)
                        }
                        Button("Show in Finder") {
                            model.showInFinder(service)
                        }
                        .disabled(service.project == nil)
                        Button("Safe Stop", role: .destructive) {
                            model.requestSafeStop(service)
                        }
                        .disabled(model.isStopping || !service.canStop)
                    }

                    if case let .denied(reason) = model.stopEligibility(for: service) {
                        Label(reason, systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
        } else {
            ContentUnavailableView(
                "Select a service",
                systemImage: "sidebar.right",
                description: Text(
                    "Service identity, exposure, project, and process details appear here."
                )
            )
        }
    }
}

private struct InspectorSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StatusPill: View {
    let title: String
    let symbol: String
    let color: Color

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
    }
}

private struct TimelinePage: View {
    @Bindable var model: PortHarborModel

    var body: some View {
        Group {
            if model.timeline.isEmpty {
                ContentUnavailableView(
                    "No recent changes",
                    systemImage: "clock.arrow.circlepath",
                    description: Text(
                        "Meaningful service changes from the last 24 hours will appear here."
                    )
                )
            } else {
                List(model.timeline) { event in
                    HStack(spacing: 12) {
                        Image(systemName: event.kind.symbol)
                            .foregroundStyle(event.kind.color)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.summary)
                            Text(event.occurredAt, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .navigationTitle("Timeline")
        .toolbar {
            ToolbarItem {
                Button(
                    "Clear Timeline",
                    systemImage: "trash",
                    role: .destructive
                ) {
                    model.clearTimeline()
                }
                .disabled(model.timeline.isEmpty)
            }
        }
    }
}

private struct MenuBarContent: View {
    @Bindable var model: PortHarborModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("PortHarbor").font(.headline)
                    Text("\(model.developmentServices.count) development services")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") {
                    model.refresh()
                }
                .labelStyle(.iconOnly)
                .disabled(model.isRefreshing)
            }

            Divider()

            if model.developmentServices.isEmpty {
                Text(
                    model.isRefreshing
                        ? "Scanning local services…"
                        : "No development services found"
                )
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ForEach(model.developmentServices.prefix(8)) { service in
                    HStack {
                        Button {
                            model.openInBrowser(service)
                        } label: {
                            Circle()
                                .fill(service.health.color)
                                .frame(width: 8, height: 8)
                            Text(service.project?.name ?? service.process.name)
                                .lineLimit(1)
                            Spacer()
                            Text(String(service.endpoint.port))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        Menu {
                            Button("Open in Browser") {
                                model.openInBrowser(service)
                            }
                            Button("Show in Finder") {
                                model.showInFinder(service)
                            }
                            .disabled(service.project == nil)
                            Divider()
                            Button("Safe Stop", role: .destructive) {
                                model.requestSafeStop(service)
                            }
                            .disabled(model.isStopping || !service.canStop)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                    }
                }
            }

            Divider()

            SettingsLink {
                Label("Settings", systemImage: "gear")
            }
            Button("Quit PortHarbor") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}

private struct LiveProcessInspector: FreshProcessInspecting {
    func identity(for pid: Int32) async throws -> ProcessIdentity? {
        try await Task.detached(priority: .utility) {
            let process = Process()
            let output = Pipe()
            let errors = Pipe()

            process.executableURL = URL(fileURLWithPath: "/bin/ps")
            process.arguments = [
                "-p", String(pid),
                "-o", "pid=,ppid=,pgid=,lstart=,comm="
            ]
            process.standardOutput = output
            process.standardError = errors

            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                return nil
            }

            let data = output.fileHandleForReading.readDataToEndOfFile()
            guard let text = String(data: data, encoding: .utf8) else {
                return nil
            }

            return PSProcessParser().parse(text)[pid]
        }.value
    }
}

private struct SettingsView: View {
    @Bindable var model: PortHarborModel

    var body: some View {
        Form {
            Picker("Refresh interval", selection: $model.refreshInterval) {
                Text("3 seconds").tag(TimeInterval(3))
                Text("5 seconds").tag(TimeInterval(5))
                Text("10 seconds").tag(TimeInterval(10))
            }
            LabeledContent("Timeline retention", value: "24 hours")
            LabeledContent("Data processing", value: "On this Mac")
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 440, height: 220)
    }
}

private extension ServiceCategory {
    var title: String {
        switch self {
        case .development: localized("Development")
        case .background: localized("Background Services")
        case .system: localized("System")
        }
    }

    var symbol: String {
        switch self {
        case .development: "hammer"
        case .background: "gearshape.2"
        case .system: "macwindow"
        }
    }
}

private extension ServiceHealth {
    var title: String {
        switch self {
        case .responding: localized("Responding")
        case .starting: localized("Starting")
        case .unreachable: localized("Unreachable")
        case .unknown: localized("Unknown")
        }
    }

    var symbol: String {
        switch self {
        case .responding: "checkmark.circle.fill"
        case .starting: "hourglass.circle.fill"
        case .unreachable: "xmark.circle.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .responding: .green
        case .starting: .orange
        case .unreachable: .red
        case .unknown: .secondary
        }
    }
}

private extension NetworkExposure {
    var title: String {
        switch self {
        case .onlyThisMac: localized("This Mac")
        case .localNetwork: localized("Local Network")
        case .allInterfaces: localized("All Interfaces")
        }
    }

    var symbol: String {
        switch self {
        case .onlyThisMac: "laptopcomputer"
        case .localNetwork: "network"
        case .allInterfaces: "globe"
        }
    }

    var color: Color {
        switch self {
        case .onlyThisMac: .green
        case .localNetwork: .orange
        case .allInterfaces: .red
        }
    }
}

private extension TimelineEventKind {
    var symbol: String {
        switch self {
        case .serviceStarted: "play.circle.fill"
        case .serviceStopped: "stop.circle.fill"
        case .portOwnerChanged: "arrow.triangle.2.circlepath"
        case .healthChanged: "heart.text.square"
        case .exposureChanged: "network"
        case .projectChanged: "folder"
        }
    }

    var color: Color {
        switch self {
        case .serviceStarted: .green
        case .serviceStopped: .red
        case .portOwnerChanged, .healthChanged, .exposureChanged, .projectChanged:
            .orange
        }
    }
}
