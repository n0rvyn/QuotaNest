import AppKit
import SwiftUI
import ArkCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = Monitor()
    var statusItem: NSStatusItem!
    let popover = NSPopover()
    var settingsWindow: NSWindow?
    var timer: Timer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: String(localized: "About QuotaNest"), action: #selector(showAbout), keyEquivalent: "").target = self
        appMenu.addItem(withTitle: String(localized: "Settings…"), action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: String(localized: "Quit QuotaNest"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        mainMenu.addItem(NativeMenus.editing())
        NSApp.mainMenu = mainMenu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "gauge.with.dots.needle.50percent", accessibilityDescription: "QuotaNest")
            button.image?.isTemplate = true
            button.target = self; button.action = #selector(togglePopover)
        }
        popover.behavior = .transient
        updatePopover()
        model.onChange = { [weak self] in self?.updateStatus(); self?.updatePopover() }
        updateStatus(); model.refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.model.refresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        if !model.configured { showSettings() }
    }
    @objc func woke() { model.refresh() }
    func updatePopover() {
        let view = MonitorView.fitted(model: model, settings: { [weak self] in self?.showSettings() }, about: { [weak self] in self?.showAbout() }, maximumBodyHeight: min(Layout.maximumBodyHeight, max(0, (NSScreen.main?.visibleFrame.height ?? Layout.panelHeight) - 160)))
        if let hosting = popover.contentViewController as? NSHostingController<MonitorView> {
            hosting.rootView = view
        } else {
            let hosting = NSHostingController(rootView: view)
            hosting.sizingOptions = [.preferredContentSize]
            popover.contentViewController = hosting
        }
        if let hosting = popover.contentViewController {
            let size = hosting.view.fittingSize
            popover.contentSize = size
        }
    }
    func updateStatus() {
        statusItem.button?.title = model.menuTitle
        statusItem.button?.toolTip = model.configured ? "QuotaNest · Ark quota remaining" : "QuotaNest · Open Settings to connect Ark"
    }
    @objc func togglePopover() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = statusItem.button { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY); popover.contentViewController?.view.window?.makeKey() }
    }
    @objc func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: CredentialsView(model: model))
            let window = NSWindow(contentViewController: controller)
            window.title = String(localized: "QuotaNest Settings")
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setContentSize(NSSize(width: Layout.settingsWidth, height: Layout.settingsHeight))
            window.center(); settingsWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === settingsWindow {
            settingsWindow = nil
            NSApp.setActivationPolicy(.accessory)
        }
    }
    @objc func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "QuotaNest", .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development", .credits: NSAttributedString(string: "norvyn.com", attributes: [.link: URL(string: "https://norvyn.com")!])])
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }
    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate(); model.stop() }
}

@MainActor func renderPreview(_ path: String, dark: Bool, mode: String) throws {
    let model = mode == "empty" ? Monitor.previewEmpty() : Monitor.preview()
    if CommandLine.arguments.contains("--collapsed") { model.resourcesExpanded = false }
    if CommandLine.arguments.contains("--resources") {
        model.plans = [.coding: Snapshot(value: Plan(windows: [QuotaWindow(id: "weekly", usedPercent: 4)]), fetchedAt: Date())]
        model.resources = Snapshot(value: (1...13).map { Resource(id: "preview-\($0)", name: "Resource \($0)", state: "Available") }, fetchedAt: Date())
    }
    if mode == "error" { model.resources.error = "Ark returned AccessDenied."; model.plans[.agent]?.error = "The Internet connection appears to be offline." }
    let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
    NSApp.appearance = appearance
    let content: AnyView
    let size: NSSize
    if mode == "settings" {
        content = AnyView(CredentialsView(model: model))
        size = NSSize(width: Layout.settingsWidth, height: Layout.settingsHeight)
    } else {
        content = AnyView(MonitorView.fitted(model: model, settings: {}, about: {}))
        size = NSSize(width: Layout.panelWidth, height: Layout.panelHeight)
    }
    let view = content
        .environment(\.colorScheme, dark ? .dark : .light)
        .background(Color(nsColor: .windowBackgroundColor))
    let controller = NSHostingController(rootView: view)
    controller.view.appearance = appearance
    controller.view.frame = NSRect(origin: .zero, size: size)
    let window = NSWindow(contentViewController: controller)
    window.setContentSize(size)
    window.displayIfNeeded()
    controller.view.layoutSubtreeIfNeeded()
    // Allow SwiftUI's measured-content preference to settle before capturing.
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    let fitted = controller.view.fittingSize
    if fitted.height > 0 { window.setContentSize(NSSize(width: size.width, height: fitted.height)) }
    controller.view.layoutSubtreeIfNeeded()
    guard let bitmap = controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds) else { throw ArkError.schema("render bitmap") }
    controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else { throw ArkError.schema("PNG") }
    try png.write(to: URL(fileURLWithPath: path))
}

let arguments = CommandLine.arguments
if arguments.contains("--version") {
    print(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0")
} else if arguments.contains("--help") {
    print("QuotaNest: native macOS menu bar monitor for Volcengine Ark.\nOpen QuotaNest.app to monitor quotas; use Settings to manage credentials.\nOptions: --help, --version")
} else if let index = arguments.firstIndex(of: "--probe"), arguments.count > index + 1 {
    let path = arguments[index + 1]
    Task {
        do {
            let credentials = try Credentials.environmentFile(URL(fileURLWithPath: path))
            let client = ArkClient(credentials: credentials)
            for kind in PlanKind.allCases {
                do {
                    let plan = try await client.plan(kind)
                    print("\(kind.title): \(plan.windows.count) quota windows")
                    for window in plan.windows { print("  \(window.id): \(window.remainingPercent)% remaining; reset: \(window.resetsAt?.description ?? "unavailable")") }
                } catch { print("\(kind.title): \(error.localizedDescription)") }
            }
            do { print("Enabled resources: \(try await client.resources().count)") }
            catch { print("Enabled resources: \(error.localizedDescription)") }
        } catch { print(error.localizedDescription) }
        exit(0)
    }
    RunLoop.main.run()
} else if let index = arguments.firstIndex(of: "--render"), arguments.count > index + 1 {
    _ = NSApplication.shared
    do {
        try renderPreview(arguments[index + 1], dark: arguments.contains("--dark"), mode: arguments.contains("--settings") ? "settings" : arguments.contains("--error") ? "error" : arguments.contains("--empty") ? "empty" : "populated")
    } catch { print(error.localizedDescription); exit(1) }
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
