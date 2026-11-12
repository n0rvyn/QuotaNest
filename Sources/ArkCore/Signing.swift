import Foundation
import CryptoKit

public struct Credentials: Codable, Sendable, Equatable {
    public let accessKey: String
    public let secretKey: String
    public init(accessKey: String, secretKey: String) {
        self.accessKey = accessKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.secretKey = secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public var isValid: Bool { !accessKey.isEmpty && !secretKey.isEmpty }
    public static func environmentFile(_ url: URL) throws -> Credentials {
        var fields: [String: String] = [:]
        for line in try String(contentsOf: url, encoding: .utf8).split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, !parts[0].trimmingCharacters(in: .whitespaces).hasPrefix("#") else { continue }
            fields[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        let result = Credentials(accessKey: fields["Access_Key_ID"] ?? "", secretKey: fields["Secret_Access_key"] ?? "")
        guard result.isValid else { throw ArkError.credentials }
        return result
    }
}

public enum VolcSigner {
    public static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func hmac(_ key: Data, _ text: String) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data(text.utf8), using: SymmetricKey(data: key)))
    }
    public static func authorization(credentials: Credentials, region: String, service: String, date: String, method: String, path: String, query: String, headers: [String: String], body: Data) -> String {
        let names = headers.keys.sorted()
        let canonicalHeaders = names.map { "\($0):\(headers[$0]!.trimmingCharacters(in: .whitespacesAndNewlines))\n" }.joined()
        let signed = names.joined(separator: ";")
        let canonical = [method, path, query, canonicalHeaders, signed, sha256(body)].joined(separator: "\n")
        let scope = "\(date.prefix(8))/\(region)/\(service)/request"
        let stringToSign = ["HMAC-SHA256", date, scope, sha256(Data(canonical.utf8))].joined(separator: "\n")
        let dateKey = hmac(Data(credentials.secretKey.utf8), String(date.prefix(8)))
        let signingKey = hmac(hmac(hmac(dateKey, region), service), "request")
        let signature = hmac(signingKey, stringToSign).map { String(format: "%02x", $0) }.joined()
        return "HMAC-SHA256 Credential=\(credentials.accessKey)/\(scope), SignedHeaders=\(signed), Signature=\(signature)"
    }
}

public enum ArkError: Error, LocalizedError, Sendable {
    case credentials
    case response(String)
    case schema(String)
    case transport(Int)
    public var errorDescription: String? {
        switch self {
        case .credentials: return "Enter your Access Key and Secret Key in Settings."
        case .response(let code): return "Ark returned \(code)."
        case .schema(let field): return "Ark returned an unrecognized response (\(field))."
        case .transport(let status): return "Ark returned HTTP \(status)."
        }
    }
}
