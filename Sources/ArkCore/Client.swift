import Foundation

public protocol ArkService: Sendable {
    func plan(_ kind: PlanKind) async throws -> Plan
    func resources() async throws -> [Resource]
}
public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}
public struct SessionTransport: HTTPTransport {
    private let session: URLSession
    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.urlCache = nil
        config.httpCookieStorage = nil
        session = URLSession(configuration: config, delegate: RedirectBlocker(), delegateQueue: nil)
    }
    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ArkError.schema("HTTP response") }
        return (data, http)
    }
}
private final class RedirectBlocker: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public struct ArkClient: ArkService, Sendable {
    private let credentials: Credentials
    private let transport: any HTTPTransport
    private let region = "cn-beijing"
    private let host = "ark.cn-beijing.volcengineapi.com"
    public init(credentials: Credentials, transport: any HTTPTransport = SessionTransport()) {
        self.credentials = credentials; self.transport = transport
    }
    public func plan(_ kind: PlanKind) async throws -> Plan {
        switch kind {
        case .agent:
            return try ArkParser.agent(await call("GetAFPUsage", payload: [:]))
        case .coding:
            guard let result = try await call("GetCodingPlanUsage", payload: [:]) else { throw ArkError.schema("Coding Plan Result") }
            return try ArkParser.coding(result)
        case .agentTeam, .codingTeam:
            let scene = kind == .agentTeam ? "agent_plan_enterprise" : ""
            guard let result = try await call("GetSeatInfo", payload: ["Scene": scene, "ProjectName": "default"]) else { return Plan(windows: []) }
            guard let seatID = result["SeatID"] as? String else { throw ArkError.schema("SeatID") }
            if seatID.isEmpty { return Plan(windows: []) }
            if kind == .agentTeam {
                guard let usage = try await call("GetSeatAFPUsage", payload: ["SeatIDs": [seatID]]) else { throw ArkError.schema("seat usage") }
                // Team response must be verified against an account with a bound seat.
                guard let rows = usage["SeatAFPUsages"] as? [[String: Any]], let row = rows.first(where: { $0["SeatID"] as? String == seatID }) else {
                    throw ArkError.schema("SeatAFPUsages")
                }
                return try ArkParser.agent(row)
            } else {
                guard let usage = try await call("GetSeatInfoUsage", payload: ["SeatID": seatID, "Scene": ""]) else { throw ArkError.schema("seat usage") }
                return try ArkParser.coding(usage)
            }
        }
    }
    public func resources() async throws -> [Resource] {
        var page = 1
        var output: [Resource] = []
        var seen: Set<String> = []
        while true {
            try Task.checkCancellation()
            guard let result = try await call("ListModelChargeItems", payload: ["PageNumber": page, "PageSize": 20]) else {
                throw ArkError.schema("resource Result")
            }
            let parsed = try ArkParser.resources(result)
            guard parsed.items.allSatisfy({ !seen.contains($0.id) }), Set(parsed.items.map(\.id)).count == parsed.items.count else {
                throw ArkError.schema("resource pagination repeated rows")
            }
            output += parsed.items
            seen.formUnion(parsed.items.map(\.id))
            if output.count >= parsed.total { break }
            guard !parsed.items.isEmpty else { throw ArkError.schema("incomplete resource pagination") }
            page += 1
        }
        return output.filter { $0.state == "Available" }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private func call(_ action: String, payload: [String: Any]) async throws -> [String: Any]? {
        guard credentials.isValid else { throw ArkError.credentials }
        let body = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .withoutEscapingSlashes])
        let query = "Action=\(action)&Version=2024-01-01"
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let date = formatter.string(from: Date())
        let headers = ["content-type": "application/json", "host": host, "x-date": date, "x-content-sha256": VolcSigner.sha256(body)]
        var components = URLComponents()
        components.scheme = "https"; components.host = host; components.path = "/"; components.percentEncodedQuery = query
        guard let url = components.url else { throw ArkError.schema("request URL") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.httpBody = body
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.setValue(VolcSigner.authorization(credentials: credentials, region: region, service: "ark", date: date,
                                                 method: "POST", path: "/", query: query, headers: headers, body: body), forHTTPHeaderField: "Authorization")
        let (data, response) = try await transport.data(for: request)
        // Never display arbitrary server text: it can contain credential material.
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if let metadata = json?["ResponseMetadata"] as? [String: Any], let error = metadata["Error"] as? [String: Any] {
            let code = error["Code"] as? String ?? "UnknownError"
            let safeCode = code.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-/")).contains($0) }
            throw ArkError.response(safeCode && code.count < 100 ? code : "UnknownError")
        }
        guard (200..<300).contains(response.statusCode) else { throw ArkError.transport(response.statusCode) }
        guard let json, json.keys.contains("Result") else { throw ArkError.schema("Result") }
        if json["Result"] is NSNull { return nil }
        guard let result = json["Result"] as? [String: Any] else { throw ArkError.schema("Result object") }
        return result
    }
}
