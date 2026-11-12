import SwiftUI
import ServiceManagement
import ArkCore

enum Layout {
    static let panelWidth: CGFloat = 390
    static let panelHeight: CGFloat = 620
    static let maximumBodyHeight: CGFloat = 500
    static let padding: CGFloat = 16
    static let gap: CGFloat = 12
    static let compact: CGFloat = 6
    static let corner: CGFloat = 10
    static let settingsWidth: CGFloat = 480
    static let settingsHeight: CGFloat = 350
    static let settingsPadding: CGFloat = 24
    static let settingsSpacing: CGFloat = 20
}
struct MonitorView: View {
    let model: Monitor
    let settings: () -> Void
    let about: () -> Void
    var bodyHeight: CGFloat = 500
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "gauge.with.dots.needle.50percent").font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("QuotaNest").font(.headline)
                    Text("Volcengine Ark").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.refreshing { ProgressView().controlSize(.small).accessibilityLabel("Refreshing") }
                Button(action: { model.refresh() }) { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).disabled(model.refreshing || !model.configured).help("Refresh now")
            }.padding(Layout.padding)
            Divider()
            ScrollView { scrollContent }
                .scrollIndicators(.visible)
                .frame(height: bodyHeight)
            Divider()
            HStack {
                Button(action: settings) { Label("Settings", systemImage: "gearshape") }
                Spacer()
                Menu {
                    Button("Open Ark Console") { NSWorkspace.shared.open(URL(string: "https://console.volcengine.com/ark/region:cn-beijing/subscription")!) }
                    Button("About QuotaNest", action: about)
                    Divider()
                    Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
                } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize()
            }.buttonStyle(.borderless).padding(Layout.padding)
        }.frame(width: Layout.panelWidth)
    }
    var scrollContent: some View {
                VStack(alignment: .leading, spacing: Layout.gap) {
                    if !model.configured {
                        ContentUnavailableView {
                            Label("Connect to Ark", systemImage: "key")
                        } description: {
                            Text("Add your Access Key and Secret Key to view plan quotas and enabled resources.")
                        } actions: { Button("Open Settings", action: settings) }
                        .fixedSize(horizontal: false, vertical: true)
                        if let error = model.credentialError { errorLabel(error) }
                    } else {
                        HStack {
                            Text("PLAN USAGE").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text("Used").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(PlanKind.allCases) { kind in
                            if let snapshot = model.plans[kind] {
                                // Hide successfully unbound team seats; keep team errors visible.
                                if kind == .agent || kind == .coding || snapshot.error != nil || !(snapshot.value?.windows.isEmpty ?? true) {
                                    planCard(kind, snapshot)
                                }
                            } else if model.refreshing && (kind == .agent || kind == .coding) {
                                HStack { Text(verbatim: kind.title); Spacer(); ProgressView().controlSize(.small) }.padding(Layout.gap)
                            }
                        }
                        Divider().padding(.vertical, Layout.compact)
                        DisclosureGroup(isExpanded: Binding(
                            get: { model.resourcesExpanded },
                            set: { model.setResourcesExpanded($0) }
                        )) {
                        if let resources = model.resources.value {
                            if resources.isEmpty { Text("No enabled resources returned.").foregroundStyle(.secondary) }
                            ForEach(resources) { resource in
                                VStack(alignment: .leading, spacing: Layout.compact) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(verbatim: resource.name).font(.subheadline).fontWeight(.semibold).textSelection(.enabled)
                                        Spacer()
                                        Label("Enabled", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.secondary)
                                    }
                                    if resource.balances.isEmpty { Text("No quota counters returned").font(.caption).foregroundStyle(.secondary) }
                                    ForEach(Array(resource.balances.enumerated()), id: \.offset) { _, balance in
                                        Text("\(balance.name): \(balance.used.formatted()) / \(balance.total.formatted()) used").font(.caption).monospacedDigit()
                                    }
                                }.padding(Layout.gap).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: Layout.corner))
                            }
                        } else if model.refreshing { ProgressView().frame(maxWidth: .infinity) }
                            if let date = model.resources.fetchedAt { updated(date, stale: model.resources.error != nil) }
                        } label: {
                            HStack {
                                Text("Enabled Resources").font(.subheadline).fontWeight(.semibold)
                                Spacer()
                                if let resources = model.resources.value {
                                    Text(verbatim: "\(resources.count)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityIdentifier("resourcesDisclosure")
                        if let error = model.resources.error { errorLabel(error) }
                    }
                }.padding(Layout.padding)
    }
    @MainActor static func fitted(model: Monitor, settings: @escaping () -> Void, about: @escaping () -> Void, maximumBodyHeight: CGFloat = 500) -> MonitorView {
        var view = MonitorView(model: model, settings: settings, about: about)
        let measurement = NSHostingView(rootView: view.scrollContent.frame(width: Layout.panelWidth).fixedSize(horizontal: false, vertical: true))
        view.bodyHeight = min(measurement.fittingSize.height, maximumBodyHeight)
        return view
    }
    private func planCard(_ kind: PlanKind, _ snapshot: Snapshot<Plan>) -> some View {
        VStack(alignment: .leading, spacing: Layout.gap) {
            HStack {
                Text(verbatim: kind.title).font(.headline)
                Spacer()
                if let tier = snapshot.value?.tier { Text(verbatim: tier).font(.caption).foregroundStyle(.secondary) }
            }
            if let error = snapshot.error { errorLabel(error) }
            if let plan = snapshot.value {
                if plan.windows.isEmpty { Text("Not enabled").font(.caption).foregroundStyle(.secondary) }
                ForEach(plan.windows) { quota in
                    VStack(alignment: .leading, spacing: Layout.compact) {
                        HStack {
                            Text(windowName(quota.id)).font(.subheadline)
                            Spacer()
                            Text("\(quota.usedPercent.formatted(.number.precision(.fractionLength(2))))% used")
                                .font(.subheadline).fontWeight(.semibold).monospacedDigit()
                        }
                        ProgressView(value: min(100, max(0, quota.usedPercent)), total: 100)
                            .tint(quota.remainingPercent <= 10 ? Color.orange : Color.accentColor)
                            .accessibilityLabel("Used quota")
                            .accessibilityValue("\(quota.usedPercent.formatted()) percent used")
                        HStack(alignment: .top) {
                            Text("\(quota.remainingPercent.formatted(.number.precision(.fractionLength(2))))% available")
                            Spacer(minLength: 0)
                            if let date = quota.resetsAt {
                                Text("Resets \(date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))")
                            } else { Text("Reset time unavailable") }
                        }.font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        if let used = quota.used, let total = quota.total {
                            Text("\(used.formatted()) / \(total.formatted()) AFP used")
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            }
            if let date = snapshot.fetchedAt { updated(date, stale: snapshot.error != nil) }
        }.padding(Layout.gap).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: Layout.corner))
    }
    private func windowName(_ id: String) -> LocalizedStringKey {
        switch id { case "session", "5h": "5 hours"; case "daily": "Daily"; case "weekly": "Weekly"; case "monthly": "Monthly"; default: LocalizedStringKey(id) }
    }
    private func errorLabel(_ text: String) -> some View {
        Label { Text(verbatim: text).textSelection(.enabled) } icon: { Image(systemName: "exclamationmark.triangle") }
            .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
    }
    private func updated(_ date: Date, stale: Bool) -> some View {
        Text("\(stale ? String(localized: "Last success") : String(localized: "Updated")) \(date.formatted(.dateTime.hour().minute()))")
            .font(.caption).foregroundStyle(.secondary)
    }
}
struct CredentialsView: View {
    let model: Monitor
    @State private var accessKey = ""
    @State private var secretKey = ""
    @State private var message: String?
    @State private var failed = false
    @State private var revealingSavedCredentials = false
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?
    var body: some View {
        VStack(alignment: .leading, spacing: Layout.settingsSpacing) {
            HStack(spacing: Layout.gap) {
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .font(.title3).foregroundStyle(.tint)
                Text("Volcengine Ark").font(.title3).fontWeight(.semibold)
            }
            VStack(alignment: .leading, spacing: Layout.compact) {
                Text("Access Key ID").font(.body)
                TextField("", text: $accessKey)
                    .accessibilityLabel("Access Key ID")
                    .labelsHidden().textFieldStyle(.roundedBorder).controlSize(.large)
                    .textContentType(.username).accessibilityIdentifier("accessKey")
            }
            VStack(alignment: .leading, spacing: Layout.compact) {
                Text("Secret Access Key").font(.body)
                Group {
                    if revealingSavedCredentials {
                        TextField("", text: $secretKey)
                    } else {
                        SecureField("", text: $secretKey).textContentType(.password)
                    }
                }
                .accessibilityLabel("Secret Access Key")
                .labelsHidden().textFieldStyle(.roundedBorder).controlSize(.large)
                .accessibilityIdentifier("secretKey")
            }
            VStack(alignment: .leading, spacing: Layout.compact) {
                Toggle("Launch at Login", isOn: Binding(
                    get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                    set: { enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch { loginError = error.localizedDescription }
                        loginStatus = SMAppService.mainApp.status
                    }
                ))
                .toggleStyle(.checkbox)
                .accessibilityIdentifier("launchAtLogin")
                if loginStatus == .requiresApproval {
                    HStack {
                        Text("Approval required").foregroundStyle(.secondary)
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                            .buttonStyle(.link)
                    }.font(.caption)
                }
            }
            Spacer(minLength: 0)
            HStack(alignment: .center, spacing: Layout.gap) {
                VStack(alignment: .leading, spacing: Layout.compact) {
                    Label(model.configured ? "Credentials saved in Keychain" : "macOS Keychain", systemImage: "lock")
                        .font(.caption).foregroundStyle(.secondary)
                    if model.configured {
                        Button(revealingSavedCredentials ? "Hide saved credentials" : "Show saved credentials") {
                            if revealingSavedCredentials {
                                accessKey = ""; secretKey = ""; revealingSavedCredentials = false
                            } else {
                                do {
                                    if let saved = try model.readSavedCredentialsForDisplay() {
                                        accessKey = saved.accessKey; secretKey = saved.secretKey
                                        revealingSavedCredentials = true; message = nil; failed = false
                                    }
                                } catch { message = error.localizedDescription; failed = true }
                            }
                        }
                        .buttonStyle(.link).font(.caption)
                        .disabled(!revealingSavedCredentials && (!accessKey.isEmpty || !secretKey.isEmpty))
                        .accessibilityIdentifier("showSavedCredentials")
                    }
                    if let message {
                        Label(message, systemImage: failed ? "exclamationmark.triangle" : "checkmark.circle")
                            .foregroundStyle(failed ? .orange : .secondary).font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Button("Save Credentials") {
                    do {
                        try model.save(Credentials(accessKey: accessKey, secretKey: secretKey))
                        accessKey = ""; secretKey = ""; revealingSavedCredentials = false
                        message = String(localized: "Saved to Keychain"); failed = false
                    } catch { message = error.localizedDescription; failed = true }
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(accessKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || secretKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .fontWeight(.regular)
        .padding(Layout.settingsPadding)
        .frame(width: Layout.settingsWidth, height: Layout.settingsHeight)
        .onAppear { loginStatus = SMAppService.mainApp.status }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginStatus = SMAppService.mainApp.status
        }
        .alert("Couldn’t Update Launch at Login", isPresented: Binding(
            get: { loginError != nil }, set: { if !$0 { loginError = nil } }
        )) {
            Button("OK", role: .cancel) { loginError = nil }
        } message: { Text(loginError ?? "") }
    }
}
