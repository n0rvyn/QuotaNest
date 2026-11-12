import Foundation
import Security

public protocol CredentialStorage: Sendable {
    func load() throws -> Credentials?
    func save(_ credentials: Credentials) throws
}
public struct KeychainStore: CredentialStorage {
    private let service: String
    public init(service: String = "com.norvyn.QuotaNest") { self.service = service }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "ark-management"]
    }
    public func load() throws -> Credentials? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status: status) }
        let credentials = try JSONDecoder().decode(Credentials.self, from: data)
        guard credentials.isValid else { throw ArkError.credentials }
        return credentials
    }
    public func save(_ credentials: Credentials) throws {
        guard credentials.isValid else { throw ArkError.credentials }
        let data = try JSONEncoder().encode(credentials)
        let update = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }
}
public struct KeychainError: Error, LocalizedError {
    public let status: OSStatus
    public var errorDescription: String? { "Keychain could not complete the operation (\(status))." }
}
