import Foundation
import SwiftUI
import ArkCore

struct Snapshot<Value: Sendable>: Sendable {
    var value: Value?
    var fetchedAt: Date?
    var error: String?
    mutating func accept(_ result: Result<Value, Error>) {
        switch result {
        case .success(let value): self.value = value; fetchedAt = Date(); error = nil
        case .failure(let error): self.error = error.localizedDescription
        }
    }
}
@MainActor @Observable final class Monitor {
    var plans: [PlanKind: Snapshot<Plan>] = [:]
    var resources = Snapshot<[Resource]>()
    var resourcesExpanded = true
    var refreshing = false
    var configured = false
    var credentialError: String?
    var onChange: (() -> Void)?
    private var generation = UUID()
    private(set) var task: Task<Void, Never>?
    private var credentials: Credentials?
    private let store: any CredentialStorage
    private let makeService: @Sendable (Credentials) -> any ArkService
    init(store: any CredentialStorage = KeychainStore(), makeService: @escaping @Sendable (Credentials) -> any ArkService = { ArkClient(credentials: $0) }) {
        self.store = store
        self.makeService = makeService
        do { credentials = try store.load(); configured = credentials != nil }
        catch { credentialError = error.localizedDescription }
    }
    var minimumRemaining: Double? {
        plans.values.flatMap { $0.value?.windows ?? [] }.map(\.remainingPercent).min()
    }
    var hasErrors: Bool { credentialError != nil || resources.error != nil || plans.values.contains { $0.error != nil } }
    var menuTitle: String {
        guard configured else { return "" }
        guard let minimumRemaining else { return " —" }
        return " \(minimumRemaining.formatted(.number.precision(.fractionLength(0))))%\(hasErrors ? " !" : "")"
    }
    // Only an explicit Show saved credentials action calls this method.
    func readSavedCredentialsForDisplay() throws -> Credentials? { try store.load() }
    func setResourcesExpanded(_ expanded: Bool) {
        resourcesExpanded = expanded
        onChange?()
    }
    func save(_ value: Credentials) throws {
        try store.save(value)
        changeCredentials(value)
    }
    func changeCredentials(_ value: Credentials) {
        task?.cancel(); generation = UUID()
        credentials = value; configured = true; credentialError = nil
        plans = [:]; resources = Snapshot(); refreshing = false
        onChange?(); refresh()
    }
    func refresh() {
        guard !refreshing, let credentials else { return }
        refreshing = true; onChange?()
        let generation = generation
        let client = makeService(credentials)
        task = Task { [weak self] in
            await withTaskGroup(of: Update.self) { group in
                for kind in PlanKind.allCases {
                    group.addTask {
                        do { return .plan(kind, .success(try await client.plan(kind))) }
                        catch { return .plan(kind, .failure(error)) }
                    }
                }
                group.addTask {
                    do { return .resources(.success(try await client.resources())) }
                    catch { return .resources(.failure(error)) }
                }
                for await update in group {
                    guard let self, self.generation == generation, !Task.isCancelled else { continue }
                    switch update {
                    case .plan(let kind, let result):
                        var snapshot = self.plans[kind] ?? Snapshot()
                        snapshot.accept(result); self.plans[kind] = snapshot
                    case .resources(let result): self.resources.accept(result)
                    }
                    self.onChange?()
                }
            }
            guard let self, self.generation == generation else { return }
            self.refreshing = false; self.onChange?()
        }
    }
    private enum Update: Sendable {
        case plan(PlanKind, Result<Plan, Error>)
        case resources(Result<[Resource], Error>)
    }
    func stop() { task?.cancel() }
    static func previewEmpty() -> Monitor { Monitor(store: PreviewStore()) }
    static func preview() -> Monitor {
        let model = Monitor(store: PreviewStore())
        model.configured = true
        model.plans[.agent] = Snapshot(value: Plan(tier: "Pro", windows: [
            QuotaWindow(id: "session", usedPercent: 38, used: 3800, total: 10000, resetsAt: Date().addingTimeInterval(7200)),
            QuotaWindow(id: "weekly", usedPercent: 68, used: 68000, total: 100000, resetsAt: Date().addingTimeInterval(86400)),
            QuotaWindow(id: "monthly", usedPercent: 24, used: 72000, total: 300000, resetsAt: Date().addingTimeInterval(864000))]), fetchedAt: Date())
        model.plans[.coding] = Snapshot(value: Plan(windows: [
            QuotaWindow(id: "session", usedPercent: 12.4, resetsAt: Date().addingTimeInterval(4200)),
            QuotaWindow(id: "weekly", usedPercent: 32, resetsAt: Date().addingTimeInterval(86400)),
            QuotaWindow(id: "monthly", usedPercent: 18, resetsAt: Date().addingTimeInterval(864000))]), fetchedAt: Date())
        model.resources = Snapshot(value: [Resource(id: "seed", name: "Doubao Seed", state: "Available", balances: [Balance(name: "FreeInference", used: 125000, total: 500000)]), Resource(id: "deepseek", name: "DeepSeek", state: "Available")], fetchedAt: Date())
        return model
    }
}
private struct PreviewStore: CredentialStorage {
    func load() throws -> Credentials? { nil }
    func save(_ credentials: Credentials) throws { throw ArkError.credentials }
}
