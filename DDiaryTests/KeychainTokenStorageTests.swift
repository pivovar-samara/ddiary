import Testing
import Foundation
import Security
@testable import DDiary

// MARK: - MockKeychainInterface

/// In-memory Keychain mock that simulates SecItem* operations using a dictionary.
/// Inherits @MainActor via SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor, satisfying the @MainActor KeychainInterface.
final class MockKeychainInterface: KeychainInterface {
    // Keyed by "service:account" → raw Data
    private var store: [String: Data] = [:]
    private(set) var addCallCount = 0
    private(set) var updateCallCount = 0
    private(set) var deleteCallCount = 0
    private(set) var copyMatchingCallCount = 0

    func itemAdd(_ attributes: CFDictionary) -> OSStatus {
        addCallCount += 1
        let dict = attributes as! [String: Any]
        guard
            let service = dict[kSecAttrService as String] as? String,
            let account = dict[kSecAttrAccount as String] as? String,
            let data = dict[kSecValueData as String] as? Data
        else { return errSecParam }
        let key = storeKey(service: service, account: account)
        if store[key] != nil { return errSecDuplicateItem }
        store[key] = data
        return errSecSuccess
    }

    func itemCopyMatching(_ query: CFDictionary, result: UnsafeMutablePointer<AnyObject?>?) -> OSStatus {
        copyMatchingCallCount += 1
        let dict = query as! [String: Any]
        guard
            let service = dict[kSecAttrService as String] as? String,
            let account = dict[kSecAttrAccount as String] as? String
        else { return errSecParam }
        let key = storeKey(service: service, account: account)
        guard let data = store[key] else { return errSecItemNotFound }
        if dict[kSecReturnData as String] as? Bool == true {
            result?.pointee = data as AnyObject
        }
        return errSecSuccess
    }

    func itemUpdate(_ query: CFDictionary, _ attributesToUpdate: CFDictionary) -> OSStatus {
        updateCallCount += 1
        let dict = query as! [String: Any]
        guard
            let service = dict[kSecAttrService as String] as? String,
            let account = dict[kSecAttrAccount as String] as? String
        else { return errSecParam }
        let key = storeKey(service: service, account: account)
        guard store[key] != nil else { return errSecItemNotFound }
        let updates = attributesToUpdate as! [String: Any]
        if let newData = updates[kSecValueData as String] as? Data {
            store[key] = newData
        }
        return errSecSuccess
    }

    func itemDelete(_ query: CFDictionary) -> OSStatus {
        deleteCallCount += 1
        let dict = query as! [String: Any]
        guard
            let service = dict[kSecAttrService as String] as? String,
            let account = dict[kSecAttrAccount as String] as? String
        else { return errSecParam }
        let key = storeKey(service: service, account: account)
        if store.removeValue(forKey: key) == nil { return errSecItemNotFound }
        return errSecSuccess
    }

    private func storeKey(service: String, account: String) -> String { "\(service):\(account)" }
}

// MARK: - Error stubs
// Defined at file scope with explicit @MainActor so they satisfy the @MainActor KeychainInterface
// requirement without relying on local-type isolation inference.

@MainActor
private struct AlwaysFailKeychain: KeychainInterface {
    func itemAdd(_ attributes: CFDictionary) -> OSStatus { errSecNotAvailable }
    func itemCopyMatching(_ query: CFDictionary, result: UnsafeMutablePointer<AnyObject?>?) -> OSStatus { errSecItemNotFound }
    func itemUpdate(_ query: CFDictionary, _ attributesToUpdate: CFDictionary) -> OSStatus { errSecNotAvailable }
    func itemDelete(_ query: CFDictionary) -> OSStatus { errSecSuccess }
}

@MainActor
private struct AlwaysFailDeleteKeychain: KeychainInterface {
    func itemAdd(_ attributes: CFDictionary) -> OSStatus { errSecSuccess }
    func itemCopyMatching(_ query: CFDictionary, result: UnsafeMutablePointer<AnyObject?>?) -> OSStatus { errSecSuccess }
    func itemUpdate(_ query: CFDictionary, _ attributesToUpdate: CFDictionary) -> OSStatus { errSecSuccess }
    func itemDelete(_ query: CFDictionary) -> OSStatus { errSecNotAvailable }
}

// MARK: - KeychainTokenStorageTests

/// @MainActor is required explicitly: Swift Testing does not inherit SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor
/// for @Suite types, so we annotate it here to run all tests on the main actor and call @MainActor
/// TokenStorage / KeychainInterface methods synchronously.
@Suite("KeychainTokenStorage")
@MainActor
struct KeychainTokenStorageTests {
    private let service = "com.test.ddiary"
    private let tokenKey = "ddiary.google.oauth.refreshToken"

    // Default value removed: default argument expressions for @MainActor parameters
    // are evaluated in a nonisolated context, so callers pass MockKeychainInterface() explicitly.
    private func makeSUT(
        keychain: MockKeychainInterface
    ) -> (KeychainTokenStorage, MockKeychainInterface) {
        (KeychainTokenStorage(service: service, keychain: keychain), keychain)
    }

    // MARK: - read

    @Test func read_returnsNil_whenNoTokenStored() {
        let (sut, _) = makeSUT(keychain: MockKeychainInterface())
        #expect(sut.read(key: tokenKey) == nil)
    }

    @Test func read_returnsToken_afterWrite() throws {
        let (sut, _) = makeSUT(keychain: MockKeychainInterface())
        try sut.write("my-refresh-token", key: tokenKey)
        #expect(sut.read(key: tokenKey) == "my-refresh-token")
    }

    @Test func read_returnsNil_afterDelete() throws {
        let (sut, _) = makeSUT(keychain: MockKeychainInterface())
        try sut.write("token", key: tokenKey)
        try sut.delete(key: tokenKey)
        #expect(sut.read(key: tokenKey) == nil)
    }

    @Test func read_isIsolatedByKey() throws {
        let (sut, _) = makeSUT(keychain: MockKeychainInterface())
        try sut.write("token-a", key: "key.a")
        try sut.write("token-b", key: "key.b")
        #expect(sut.read(key: "key.a") == "token-a")
        #expect(sut.read(key: "key.b") == "token-b")
    }

    // MARK: - write

    @Test func write_addsNewItem_whenNoneExists() throws {
        let mock = MockKeychainInterface()
        let (sut, _) = makeSUT(keychain: mock)
        try sut.write("token", key: tokenKey)
        #expect(mock.addCallCount == 1)
        #expect(mock.updateCallCount == 0)
    }

    @Test func write_updatesExistingItem_whenOneExists() throws {
        let mock = MockKeychainInterface()
        let (sut, _) = makeSUT(keychain: mock)
        try sut.write("token-v1", key: tokenKey)
        try sut.write("token-v2", key: tokenKey)
        #expect(mock.addCallCount == 1)
        #expect(mock.updateCallCount == 1)
        #expect(sut.read(key: tokenKey) == "token-v2")
    }

    @Test func write_throwsWriteFailed_onKeychainError() {
        let sut = KeychainTokenStorage(service: service, keychain: AlwaysFailKeychain())
        #expect(throws: KeychainTokenStorageError.writeFailed(errSecNotAvailable)) {
            try sut.write("token", key: tokenKey)
        }
    }

    // MARK: - delete

    @Test func delete_removesExistingItem() throws {
        let mock = MockKeychainInterface()
        let (sut, _) = makeSUT(keychain: mock)
        try sut.write("token", key: tokenKey)
        try sut.delete(key: tokenKey)
        #expect(mock.deleteCallCount == 1)
        #expect(sut.read(key: tokenKey) == nil)
    }

    @Test func delete_succeedsGracefully_whenItemDoesNotExist() throws {
        let (sut, _) = makeSUT(keychain: MockKeychainInterface())
        // No throw ⟹ test passes; any throw ⟹ test fails automatically.
        try sut.delete(key: tokenKey)
    }

    @Test func delete_throwsDeleteFailed_onKeychainError() {
        let sut = KeychainTokenStorage(service: service, keychain: AlwaysFailDeleteKeychain())
        #expect(throws: KeychainTokenStorageError.deleteFailed(errSecNotAvailable)) {
            try sut.delete(key: tokenKey)
        }
    }
}
