import Testing
import Foundation
@testable import ArkCore

@Test func signatureMatchesSuppliedPDFVector() {
    // Supplied signing guide pp. 51–55: public reference secret/request.
    // Access ID is a placeholder; it is not part of the signature calculation.
    let credentials = Credentials(accessKey: "example-access-key", secretKey: "WkRZeE1EQmxPVGhsWWpWak5HVmtNbUUxTXpZeU9UVXlOMlE1TmpZeVlqTQ==")
    let header = VolcSigner.authorization(credentials: credentials, region: "cn-beijing", service: "iam", date: "20240619T071306Z", method: "GET", path: "/", query: "Action=ListUsers&Limit=10&Offset=0&Version=2018-01-01", headers: ["host": "iam.volcengineapi.com", "x-date": "20240619T071306Z"], body: Data())
    #expect(header.hasSuffix("Signature=e31c4558bcfe08a286001f59cedbf0791ffd0b2362f10e55ee2627467bcdde93"))
}
@Test func codingPercentageAndResetUnits() throws {
    let plan = try ArkParser.coding(["QuotaUsage": [["Level": "weekly", "Percent": 68.25, "ResetTimestamp": 1795000000]], "UpdateTimestamp": 1794000000000])
    #expect(plan.windows[0].remainingPercent == 31.75)
    #expect(plan.windows[0].resetsAt == Date(timeIntervalSince1970: 1795000000))
    #expect(plan.updatedAt == Date(timeIntervalSince1970: 1794000000))
    #expect(plan.windows[0].total == nil)
}
@Test func malformedQuotaDoesNotBecomeUnusedQuota() {
    #expect(throws: (any Error).self) { try ArkParser.coding(["QuotaUsage": [["Level": "session"]]]) }
    #expect(throws: (any Error).self) { try ArkParser.coding(["QuotaUsage": [["Level": "session", "Percent": true]]]) }
    #expect(throws: (any Error).self) { try ArkParser.coding(["QuotaUsage": [["Level": "session", "Percent": -1]]]) }
    #expect(throws: (any Error).self) { try ArkParser.coding([:]) }
}
@Test func agentAndCodingRemainDistinct() throws {
    let agent = try ArkParser.agent(["Tier": "medium", "AFPFiveHour": ["Used": 250, "Quota": 1000, "ResetTime": 1795000000000]])
    #expect(agent.windows[0].remainingPercent == 75)
    #expect(agent.windows[0].total == 1000)
    #expect(agent.windows[0].resetsAt == Date(timeIntervalSince1970: 1795000000))
    #expect(try ArkParser.agent(nil).windows.isEmpty)
    #expect(throws: (any Error).self) { try ArkParser.agent(["newSchema": 1]) }
}
@Test func overagePreservedAndZeroQuotaUnavailable() throws {
    let agent = try ArkParser.agent(["AFPWeekly": ["Used": 110, "Quota": 100], "AFPFiveHour": ["Used": 0, "Quota": 0]])
    #expect(agent.windows.count == 1)
    #expect(abs(agent.windows[0].remainingPercent - -10) < 0.000001)
}
@Test func enabledResourceWithoutBalanceRemainsVisible() throws {
    let page = try ArkParser.resources(["Items": [["FoundationModelName": "model-1", "State": "Available", "DisplayName": "Model"]], "TotalCount": 1])
    #expect(page.items.count == 1)
    #expect(page.items[0].balances.isEmpty)
}
@Test func badResourceSchemaFailsExplicitly() {
    #expect(throws: (any Error).self) { try ArkParser.resources(["Items": [], "TotalCount": -1]) }
    #expect(throws: (any Error).self) { try ArkParser.resources(["Items": [["DisplayName": "Missing ID"]], "TotalCount": 1]) }
}
private actor FixtureTransport: HTTPTransport {
    var requests: [URLRequest] = []
    let responses: [Data]
    init(_ responses: [String]) { self.responses = responses.map { Data($0.utf8) } }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let index = requests.count
        requests.append(request)
        guard index < responses.count else { throw ArkError.schema("fixture exhausted") }
        return (responses[index], HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
@Test func resourcePaginationAndAvailableFiltering() async throws {
    let transport = FixtureTransport([
        #"{"Result":{"Items":[{"FoundationModelName":"enabled","State":"Available"}],"TotalCount":2}}"#,
        #"{"Result":{"Items":[{"FoundationModelName":"disabled","State":"Unavailable"}],"TotalCount":2}}"#
    ])
    let client = ArkClient(credentials: Credentials(accessKey: "test-key", secretKey: "test-secret"), transport: transport)
    let resources = try await client.resources()
    #expect(resources.map(\.id) == ["enabled"])
    let requests = await transport.requests
    #expect(requests.count == 2)
    #expect(requests.allSatisfy { $0.httpMethod == "POST" && $0.url?.host == "ark.cn-beijing.volcengineapi.com" })
    #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization")?.hasPrefix("HMAC-SHA256 Credential=test-key/") == true })
    let page2 = try #require(try JSONSerialization.jsonObject(with: requests[1].httpBody!) as? [String: Int])
    #expect(page2["PageNumber"] == 2)
}
@Test func repeatedPageCannotSilentlyComplete() async {
    let transport = FixtureTransport(Array(repeating: #"{"Result":{"Items":[{"FoundationModelName":"enabled","State":"Available"}],"TotalCount":2}}"#, count: 2))
    let client = ArkClient(credentials: Credentials(accessKey: "test-key", secretKey: "test-secret"), transport: transport)
    await #expect(throws: (any Error).self) { try await client.resources() }
}
@Test func rawServerMessageNeverDisplayed() async {
    let transport = FixtureTransport([#"{"ResponseMetadata":{"Error":{"Code":"AccessDenied","Message":"secret-material"}}}"#])
    let client = ArkClient(credentials: Credentials(accessKey: "test-key", secretKey: "test-secret"), transport: transport)
    do { _ = try await client.plan(.coding); Issue.record("Expected rejection") }
    catch { #expect(error.localizedDescription == "Ark returned AccessDenied.") }
}

@Test func smallUsedPercentageIsNotTreatedAsFractionOrRemaining() throws {
    let plan = try ArkParser.coding(["QuotaUsage": [
        ["Level": "session", "Percent": 0.0263225],
        ["Level": "weekly", "Percent": 3.862982],
        ["Level": "monthly", "Percent": 2.7709586666666666]
    ]])
    let weekly = try #require(plan.windows.first { $0.id == "weekly" })
    #expect(abs(weekly.usedPercent - 3.862982) < 0.0000001)
    #expect(abs(weekly.remainingPercent - 96.137018) < 0.0000001)
    #expect(plan.windows[0].usedPercent < 0.03)
}
@Test func resourceBalancesUseQuotaCountersAndNeverPrices() throws {
    let page = try ArkParser.resources(["TotalCount": 1, "Items": [[
        "FoundationModelName": "synthetic-model", "State": "Available",
        "ChargeItems": [["Type": "InferencePrompt", "Price": 0.012]],
        "ResourcePackItems": [
            ["Type": "FreeInference", "Total": 500000, "Consumed": 53603],
            ["Type": "DataPermission", "Total": 1000000, "Consumed": 100000]
        ]
    ]]])
    #expect(page.items[0].balances.count == 2)
    #expect(page.items[0].balances[0].used == 53603)
    #expect(page.items[0].balances[0].remaining == 446397)
    #expect(page.items[0].balances[1].name == "Data permission pack")
}

@Test func teamDiscoverySuppliesRequiredProjectContext() async throws {
    let transport = FixtureTransport([#"{"Result":{"SeatID":""}}"#])
    let client = ArkClient(credentials: Credentials(accessKey: "test-key", secretKey: "test-secret"), transport: transport)
    #expect(try await client.plan(.agentTeam).windows.isEmpty)
    let requests = await transport.requests
    let body = try #require(try JSONSerialization.jsonObject(with: requests[0].httpBody!) as? [String: String])
    #expect(body["ProjectName"] == "default")
    #expect(body["Scene"] == "agent_plan_enterprise")
    #expect(body["SeatID"] == nil)
}
@Test func seatAFPUsesOfficialResponseWrapper() async throws {
    let transport = FixtureTransport([
        #"{"Result":{"SeatID":"synthetic-seat"}}"#,
        #"{"Result":{"SeatAFPUsages":[{"SeatID":"synthetic-seat","PlanType":"Max","AFPFiveHour":{"Quota":"100.0","Used":"42.3","ResetTime":1778806800000}}]}}"#
    ])
    let client = ArkClient(credentials: Credentials(accessKey: "test-key", secretKey: "test-secret"), transport: transport)
    let plan = try await client.plan(.agentTeam)
    #expect(plan.windows[0].usedPercent == 42.3)
    #expect(plan.windows[0].remainingPercent == 57.7)
}
@Test func realParameterErrorCodeIsNotReplacedWithUnknownError() async {
    let transport = FixtureTransport([#"{"ResponseMetadata":{"Error":{"Code":"InvalidParameter.SeatID/ProjectName","Message":"request must pass SeatID or ProjectName, not both"}}}"#])
    let client = ArkClient(credentials: Credentials(accessKey: "test-key", secretKey: "test-secret"), transport: transport)
    do { _ = try await client.plan(.agentTeam); Issue.record("Expected API error") }
    catch { #expect(error.localizedDescription == "Ark returned InvalidParameter.SeatID/ProjectName.") }
}
