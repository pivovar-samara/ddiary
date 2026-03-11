import Foundation
import Security

// MARK: - TokenStorage

/// Read/write/delete interface for a single string value associated with a key.
/// Isolated to `@MainActor` because all callers are main-actor-bound repositories.
@MainActor
protocol TokenStorage {
    func read(key: String) -> String?
    func write(_ token: String, key: String) throws
    func delete(key: String) throws
}

// MARK: - KeychainInterface

/// Abstraction over Security framework functions, enabling substitution in unit tests.
/// Isolated to `@MainActor` to match `KeychainTokenStorage` and all its callers.
@MainActor
protocol KeychainInterface {
    func itemAdd(_ attributes: CFDictionary) -> OSStatus
    func itemCopyMatching(_ query: CFDictionary, result: UnsafeMutablePointer<AnyObject?>?) -> OSStatus
    func itemUpdate(_ query: CFDictionary, _ attributesToUpdate: CFDictionary) -> OSStatus
    func itemDelete(_ query: CFDictionary) -> OSStatus
}

// MARK: - SystemKeychain

/// Live implementation that delegates to the Security framework.
struct SystemKeychain: KeychainInterface {
    func itemAdd(_ attributes: CFDictionary) -> OSStatus {
        SecItemAdd(attributes, nil)
    }

    func itemCopyMatching(_ query: CFDictionary, result: UnsafeMutablePointer<AnyObject?>?) -> OSStatus {
        SecItemCopyMatching(query, result as UnsafeMutablePointer<CFTypeRef?>?)
    }

    func itemUpdate(_ query: CFDictionary, _ attributesToUpdate: CFDictionary) -> OSStatus {
        SecItemUpdate(query, attributesToUpdate)
    }

    func itemDelete(_ query: CFDictionary) -> OSStatus {
        SecItemDelete(query)
    }
}

// MARK: - KeychainTokenStorageError

enum KeychainTokenStorageError: Error, Equatable {
    case writeFailed(OSStatus)
    case deleteFailed(OSStatus)
}

// MARK: - KeychainTokenStorage

/// Stores a single string token per key in the iOS/macOS Keychain.
/// Tokens are accessible when the device is unlocked (`kSecAttrAccessibleWhenUnlocked`).
final class KeychainTokenStorage: TokenStorage {
    private let service: String
    private let keychain: any KeychainInterface

    init(
        service: String = Bundle.main.bundleIdentifier ?? "com.ddiary.app",
        keychain: any KeychainInterface = SystemKeychain()
    ) {
        self.service = service
        self.keychain = keychain
    }

    func read(key: String) -> String? {
        let query = baseQuery(key: key).merging([
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ], uniquingKeysWith: { $1 })

        var result: AnyObject?
        let status = keychain.itemCopyMatching(query as CFDictionary, result: &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return token
    }

    func write(_ token: String, key: String) throws {
        guard let data = token.data(using: .utf8) else { return }

        let lookupQuery = baseQuery(key: key)
        let exists = keychain.itemCopyMatching(lookupQuery as CFDictionary, result: nil) == errSecSuccess

        let status: OSStatus
        if exists {
            let update = [kSecValueData as String: data] as CFDictionary
            status = keychain.itemUpdate(lookupQuery as CFDictionary, update)
        } else {
            let addQuery = baseQuery(key: key).merging([
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            ], uniquingKeysWith: { $1 })
            status = keychain.itemAdd(addQuery as CFDictionary)
        }

        guard status == errSecSuccess else {
            throw KeychainTokenStorageError.writeFailed(status)
        }
    }

    func delete(key: String) throws {
        let query = baseQuery(key: key)
        let status = keychain.itemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainTokenStorageError.deleteFailed(status)
        }
    }

    // MARK: - Private

    private func baseQuery(key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}
