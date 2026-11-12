import Testing
import Foundation
import ArkCore
@testable import QuotaNest

private struct TestStore: CredentialStorage {
    let credentials: Credentials?
    func load() throws -> Credentials? { credentials }
    func save(_ credentials: Credentials) throws {}
}
private actor DelayedService: ArkService {
    let percent: Double
    var continuations: [CheckedContinuation<Plan, Never>] = []
    var resourceContinuation: CheckedContinuation<[Resource], Never>?
    init(percent: Double) { self.percent = percent }
    func plan(_ kind: PlanKind) async throws -> Plan {
        // Intentionally ignores cancellation to model a late HTTP completion.
        await withCheckedContinuation { continuations.append($0) }
    }
    func resources() async throws -> [Resource] {
        await withCheckedContinuation { resourceContinuation = $0 }
    }
    func ready() -> Bool { continuations.count == PlanKind.allCases.count && resourceContinuation != nil }
    func finish() {
        for c in continuations { c.resume(returning: Plan(windows: [QuotaWindow(id: "session", usedPercent: percent)])) }
        continuations.removeAll()
        resourceContinuation?.resume(returning: []); resourceContinuation = nil
    }
}
@Test @MainActor func credentialSwitchRejectsLatePreviousAccountResults() async throws {
    let old = DelayedService(percent: 90)
    let new = DelayedService(percent: 20)
    let initial = Credentials(accessKey: "old", secretKey: "test-secret")
    let model = Monitor(store: TestStore(credentials: initial), makeService: { $0.accessKey == "old" ? old : new })
    model.refresh()
    let oldTask = model.task
    while !(await old.ready()) { await Task.yield() }
    try model.save(Credentials(accessKey: "new", secretKey: "test-secret"))
    #expect(model.plans.isEmpty)
    #expect(model.resources.value == nil)
    let newTask = model.task
    while !(await new.ready()) { await Task.yield() }
    await new.finish()
    await newTask?.value
    #expect(model.minimumRemaining == 80)
    await old.finish()
    await oldTask?.value
    #expect(model.minimumRemaining == 80)
    #expect(!model.refreshing)
}
@Test func failedRefreshKeepsPreviousValueAndTimestamp() {
    let previous = Date(timeIntervalSince1970: 1234)
    var snapshot = Snapshot(value: 42, fetchedAt: previous)
    snapshot.accept(.failure(ArkError.response("AccessDenied")))
    #expect(snapshot.value == 42)
    #expect(snapshot.fetchedAt == previous)
    #expect(snapshot.error != nil)
    snapshot.accept(.success(12))
    #expect(snapshot.value == 12)
    #expect(snapshot.error == nil)
}

import AppKit
import SwiftUI

@Test @MainActor func emptyPopoverFitsContentAndLongContentScrolls() {
    _ = NSApplication.shared
    let empty = MonitorView.fitted(model: Monitor.previewEmpty(), settings: {}, about: {})
    #expect(empty.bodyHeight > 100)
    #expect(empty.bodyHeight < 400)
    let full = MonitorView.fitted(model: Monitor.preview(), settings: {}, about: {}, maximumBodyHeight: 200)
    #expect(full.bodyHeight == 200)
}
@Test @MainActor func settingsHasVisibleNativeContentHeight() {
    _ = NSApplication.shared
    let host = NSHostingView(rootView: CredentialsView(model: Monitor.previewEmpty()))
    #expect(host.fittingSize.width == Layout.settingsWidth)
    #expect(host.fittingSize.height >= Layout.settingsHeight)
}

private final class CountingCredentialStore: CredentialStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var loads = 0
    var loadCount: Int { lock.lock(); defer { lock.unlock() }; return loads }
    func load() throws -> Credentials? {
        lock.lock(); loads += 1; lock.unlock()
        return Credentials(accessKey: "synthetic-access-key", secretKey: "synthetic-secret")
    }
    func save(_ credentials: Credentials) throws {}
}
@Test @MainActor func settingsPresentationDoesNotReadKeychainAndExplicitShowDoes() throws {
    _ = NSApplication.shared
    let store = CountingCredentialStore()
    let model = Monitor(store: store)
    #expect(store.loadCount == 1) // Initial retrieval for background monitoring.
    let controller = NSHostingController(rootView: CredentialsView(model: model))
    _ = controller.view
    controller.viewWillAppear()
    controller.view.layoutSubtreeIfNeeded()
    controller.viewDidAppear()
    #expect(store.loadCount == 1)
    let saved = try model.readSavedCredentialsForDisplay()
    #expect(saved?.isValid == true)
    #expect(store.loadCount == 2)
}
@Test @MainActor func resourceDisclosureShrinksPopoverAndExpandedListRemainsBounded() {
    _ = NSApplication.shared
    let model = Monitor.previewEmpty()
    model.configured = true
    model.resources = Snapshot(value: (1...40).map {
        Resource(id: "synthetic-\($0)", name: "Resource \($0)", state: "Available")
    }, fetchedAt: Date())
    let expanded = MonitorView.fitted(model: model, settings: {}, about: {}, maximumBodyHeight: Layout.maximumBodyHeight)
    #expect(expanded.bodyHeight == Layout.maximumBodyHeight)
    var resizeRequested = false
    model.onChange = { resizeRequested = true }
    model.setResourcesExpanded(false)
    let collapsed = MonitorView.fitted(model: model, settings: {}, about: {}, maximumBodyHeight: Layout.maximumBodyHeight)
    #expect(resizeRequested)
    #expect(collapsed.bodyHeight < expanded.bodyHeight)
    #expect(model.resources.value?.count == 40)
}
