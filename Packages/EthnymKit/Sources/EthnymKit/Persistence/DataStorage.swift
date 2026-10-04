import Foundation
import Security
import Synchronization

/// Somewhere to keep JSON blobs by key.
public protocol DataStorage: Sendable {
    func load(_ key: String) throws -> Data?
    func save(_ data: Data, for key: String) throws
    func remove(_ key: String) throws
}

public extension DataStorage {
    func decode<Value: Decodable>(_ type: Value.Type, for key: String) -> Value? {
        guard let data = try? load(key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func encode(_ value: some Encodable, for key: String) throws {
        try save(JSONEncoder().encode(value), for: key)
    }
}

/// The Keychain, for wallet keystores. Items stay on this device: they are excluded from iCloud
/// Keychain and from backups restored to another device, and are readable only while unlocked.
public struct KeychainStorage: DataStorage {
    public let service: String

    public init(service: String) {
        self.service = service
    }

    public struct Failure: LocalizedError {
        public let status: OSStatus

        public var errorDescription: String? {
            "Keychain error \(status): \(SecCopyErrorMessageString(status, nil) as String? ?? "unknown")"
        }
    }

    private func query(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    public func load(_ key: String) throws -> Data? {
        var query = query(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure(status: status) }
        return result as? Data
    }

    public func save(_ data: Data, for key: String) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        var status = SecItemUpdate(query(key) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query(key).merging(attributes) { $1 } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    public func remove(_ key: String) throws {
        let status = SecItemDelete(query(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
    }
}

/// JSON files in Application Support, encrypted at rest while the device is locked.
public struct FileStorage: DataStorage {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// `Application Support/ETHnym`.
    public static var applicationSupport: FileStorage {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return FileStorage(directory: base.appending(path: "ETHnym", directoryHint: .isDirectory))
    }

    private func url(_ key: String) -> URL {
        directory.appending(path: "\(key).json")
    }

    public func load(_ key: String) throws -> Data? {
        let url = url(key)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        return try Data(contentsOf: url)
    }

    public func save(_ data: Data, for key: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: url(key), options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url(key), options: .atomic)
        #endif
    }

    public func remove(_ key: String) throws {
        let url = url(key)
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

/// For tests and previews.
public final class InMemoryStorage: DataStorage {
    private let values = Mutex<[String: Data]>([:])

    public init(_ initial: [String: Data] = [:]) {
        values.withLock { $0 = initial }
    }

    public func load(_ key: String) throws -> Data? {
        values.withLock { $0[key] }
    }

    public func save(_ data: Data, for key: String) throws {
        values.withLock { $0[key] = data }
    }

    public func remove(_ key: String) throws {
        _ = values.withLock { $0.removeValue(forKey: key) }
    }
}
