import Foundation

public struct QuotaWindow: Identifiable, Sendable, Equatable {
    public let id: String
    public let usedPercent: Double
    public let used: Double?
    public let total: Double?
    public let resetsAt: Date?
    public var remainingPercent: Double { 100 - usedPercent }
    public init(id: String, usedPercent: Double, used: Double? = nil, total: Double? = nil, resetsAt: Date? = nil) {
        self.id = id; self.usedPercent = usedPercent; self.used = used; self.total = total; self.resetsAt = resetsAt
    }
}
public struct Plan: Sendable, Equatable {
    public let tier: String?
    public let windows: [QuotaWindow]
    public let updatedAt: Date?
    public init(tier: String? = nil, windows: [QuotaWindow], updatedAt: Date? = nil) {
        self.tier = tier; self.windows = windows; self.updatedAt = updatedAt
    }
}
public struct Resource: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let state: String
    public let balances: [Balance]
    public init(id: String, name: String, state: String, balances: [Balance] = []) {
        self.id = id; self.name = name; self.state = state; self.balances = balances
    }
}
public struct Balance: Sendable, Equatable {
    public let name: String
    public let used: Double
    public let total: Double
    public var remaining: Double { total - used }
    public init(name: String, used: Double, total: Double) { self.name = name; self.used = used; self.total = total }
}
public enum PlanKind: String, CaseIterable, Sendable, Identifiable {
    case agent, coding, agentTeam, codingTeam
    public var id: String { rawValue }
    public var title: String {
        switch self { case .agent: "Agent Plan"; case .coding: "Coding Plan"; case .agentTeam: "Agent Plan · Team"; case .codingTeam: "Coding Plan · Team" }
    }
}

// JSON stays inside the service/parser boundary; views receive Sendable value models.
public enum ArkParser {
    public static func number(_ value: Any?) -> Double? {
        guard !(value is NSNull), let value else { return nil }
        if let value = value as? NSNumber {
            guard CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
            let n = value.doubleValue; return n.isFinite ? n : nil
        }
        if let s = value as? String, let n = Double(s), n.isFinite { return n }
        return nil
    }
    public static func date(_ value: Any?) -> Date? {
        guard let n = number(value), n > 0 else { return nil }
        return Date(timeIntervalSince1970: n > 100_000_000_000 ? n / 1000 : n)
    }
    public static func coding(_ result: [String: Any]) throws -> Plan {
        guard let rows = result["QuotaUsage"] as? [[String: Any]] else { throw ArkError.schema("QuotaUsage") }
        let windows = try rows.map { row -> QuotaWindow in
            guard let level = row["Level"] as? String, !level.isEmpty,
                  let percent = number(row["Percent"]), percent >= 0 else { throw ArkError.schema("quota percentage") }
            return QuotaWindow(id: level, usedPercent: percent, resetsAt: date(row["ResetTimestamp"]))
        }
        guard Set(windows.map(\.id)).count == windows.count else { throw ArkError.schema("duplicate quota window") }
        return Plan(windows: sorted(windows), updatedAt: date(result["UpdateTimestamp"]))
    }
    public static func agent(_ result: [String: Any]?) throws -> Plan {
        guard let result else { return Plan(windows: []) }
        let fields = [("AFPFiveHour", "session"), ("AFPDaily", "daily"), ("AFPWeekly", "weekly"), ("AFPMonthly", "monthly")]
        var windows: [QuotaWindow] = []
        for (key, level) in fields {
            guard let raw = result[key], !(raw is NSNull) else { continue }
            guard let bucket = raw as? [String: Any], let used = number(bucket["Used"]),
                  let total = number(bucket["Quota"] ?? bucket["Total"]), used >= 0, total >= 0 else { throw ArkError.schema(key) }
            // A zero quota is unavailable; never divide by zero or invent remaining quota.
            if total == 0 { continue }
            windows.append(QuotaWindow(id: level, usedPercent: used / total * 100, used: used, total: total,
                                       resetsAt: date(bucket["ResetTime"] ?? bucket["ResetTimestamp"])))
        }
        guard fields.contains(where: { result[$0.0] != nil }) else { throw ArkError.schema("AFP quota windows") }
        return Plan(tier: result["Tier"] as? String ?? result["PlanType"] as? String, windows: sorted(windows))
    }
    private static func sorted(_ windows: [QuotaWindow]) -> [QuotaWindow] {
        let order = ["session", "5h", "daily", "weekly", "monthly"]
        return windows.sorted { (order.firstIndex(of: $0.id) ?? order.count) < (order.firstIndex(of: $1.id) ?? order.count) }
    }
    public static func resources(_ result: [String: Any]) throws -> (items: [Resource], total: Int) {
        guard let rows = result["Items"] as? [[String: Any]], let total = number(result["TotalCount"]), total >= 0, total.rounded() == total else {
            throw ArkError.schema("resource Items/TotalCount")
        }
        let items = try rows.map { row -> Resource in
            guard let id = row["FoundationModelName"] as? String, !id.isEmpty, let state = row["State"] as? String else { throw ArkError.schema("model identity/state") }
            var balances: [Balance] = []
            if let free = row["InferenceFreeUsage"] as? [String: Any] {
                guard let total = number(free["Total"]), let used = number(free["Consumed"]), total >= 0, used >= 0 else {
                    throw ArkError.schema("InferenceFreeUsage")
                }
                balances.append(Balance(name: "Free inference", used: used, total: total))
            }
            if let packs = row["ResourcePackItems"] as? [[String: Any]] {
                for pack in packs {
                    guard let type = pack["Type"] as? String, let total = number(pack["Total"]), let used = number(pack["Consumed"]), total >= 0, used >= 0 else {
                        throw ArkError.schema("ResourcePackItems")
                    }
                    let label = type == "FreeInference" ? "Free inference pack" : type == "DataPermission" ? "Data permission pack" : type
                    balances.append(Balance(name: label, used: used, total: total))
                }
            }
            return Resource(id: id, name: row["DisplayName"] as? String ?? id, state: state, balances: balances)
        }
        return (items, Int(total))
    }
}
import CoreFoundation
