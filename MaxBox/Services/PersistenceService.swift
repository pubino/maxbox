import Foundation

// MARK: - Errors

enum PersistenceError: Error, LocalizedError {
    case encodingFailed(Error)
    case decodingFailed(Error)
    case writeFailed(Error)
    case directoryCreationFailed(Error)
    case versionMismatch(found: Int, expected: Int)

    var errorDescription: String? {
        switch self {
        case .encodingFailed(let e): return "Encoding failed: \(e.localizedDescription)"
        case .decodingFailed(let e): return "Decoding failed: \(e.localizedDescription)"
        case .writeFailed(let e): return "Write failed: \(e.localizedDescription)"
        case .directoryCreationFailed(let e): return "Directory creation failed: \(e.localizedDescription)"
        case .versionMismatch(let found, let expected): return "Version mismatch: found \(found), expected \(expected)"
        }
    }
}

// MARK: - Protocol

protocol PersistenceServiceProtocol {
    func saveAccounts(_ accounts: [PersistableAccount]) throws
    func loadAccounts() throws -> [PersistableAccount]
    func deleteAccounts() throws

    func saveSelection(_ selection: SidebarSelection) throws
    func loadSelection() throws -> SidebarSelection?

    func saveMailboxCache(_ cache: PersistableMailboxCache, for selection: SidebarSelection) throws
    func loadMailboxCache(for selection: SidebarSelection) throws -> PersistableMailboxCache?
    func deleteMailboxCache(for selection: SidebarSelection) throws
    func deleteAllMailboxCaches() throws

    func savePreferences(_ preferences: UserPreferences) throws
    func loadPreferences() throws -> UserPreferences
}

// MARK: - Implementation

final class PersistenceService: PersistenceServiceProtocol {
    static let diskCacheTTL: TimeInterval = 3600 // 1 hour

    private let fileManager: FileManager
    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private let baseDirectory: URL
    private let cacheDirectory: URL

    private static let selectionKey = "maxbox.lastSelection"
    private static let preferencesKey = "maxbox.preferences"
    private static let accountsFilename = "accounts.json"

    init(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        baseDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.defaults = defaults

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        if let base = baseDirectory {
            self.baseDirectory = base
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.baseDirectory = appSupport.appendingPathComponent("MaxBox")
        }
        self.cacheDirectory = self.baseDirectory.appendingPathComponent("cache")
    }

    // MARK: - Accounts

    func saveAccounts(_ accounts: [PersistableAccount]) throws {
        let store = VersionedStore(payload: accounts)
        try writeJSON(store, to: baseDirectory.appendingPathComponent(Self.accountsFilename))
    }

    func loadAccounts() throws -> [PersistableAccount] {
        let url = baseDirectory.appendingPathComponent(Self.accountsFilename)
        guard let store: VersionedStore<[PersistableAccount]> = try readJSON(from: url) else {
            return []
        }
        guard store.version == VersionedStore<[PersistableAccount]>.currentVersion else {
            // Silently discard future/incompatible versions
            try? fileManager.removeItem(at: url)
            return []
        }
        return store.payload
    }

    func deleteAccounts() throws {
        let url = baseDirectory.appendingPathComponent(Self.accountsFilename)
        try? fileManager.removeItem(at: url)
    }

    // MARK: - Selection (UserDefaults)

    func saveSelection(_ selection: SidebarSelection) throws {
        let data = try encoder.encode(selection)
        defaults.set(data, forKey: Self.selectionKey)
    }

    func loadSelection() throws -> SidebarSelection? {
        guard let data = defaults.data(forKey: Self.selectionKey) else {
            return nil
        }
        return try decoder.decode(SidebarSelection.self, from: data)
    }

    // MARK: - Mailbox Cache

    func saveMailboxCache(_ cache: PersistableMailboxCache, for selection: SidebarSelection) throws {
        let store = VersionedStore(payload: cache)
        let url = cacheFileURL(for: selection)
        try writeJSON(store, to: url)
    }

    func loadMailboxCache(for selection: SidebarSelection) throws -> PersistableMailboxCache? {
        let url = cacheFileURL(for: selection)
        guard let store: VersionedStore<PersistableMailboxCache> = try readJSON(from: url) else {
            return nil
        }
        guard store.version == VersionedStore<PersistableMailboxCache>.currentVersion else {
            try? fileManager.removeItem(at: url)
            return nil
        }
        return store.payload
    }

    func deleteMailboxCache(for selection: SidebarSelection) throws {
        let url = cacheFileURL(for: selection)
        try? fileManager.removeItem(at: url)
    }

    func deleteAllMailboxCaches() throws {
        if fileManager.fileExists(atPath: cacheDirectory.path) {
            try fileManager.removeItem(at: cacheDirectory)
        }
    }

    // MARK: - Preferences (UserDefaults)

    func savePreferences(_ preferences: UserPreferences) throws {
        let data = try encoder.encode(preferences)
        defaults.set(data, forKey: Self.preferencesKey)
    }

    func loadPreferences() throws -> UserPreferences {
        guard let data = defaults.data(forKey: Self.preferencesKey) else {
            return .default
        }
        return try decoder.decode(UserPreferences.self, from: data)
    }

    // MARK: - Helpers

    private func cacheFileURL(for selection: SidebarSelection) -> URL {
        cacheDirectory.appendingPathComponent("\(selection.cacheKey).json")
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: dir.path) {
            do {
                try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                throw PersistenceError.directoryCreationFailed(error)
            }
        }
        do {
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)
        } catch let error as EncodingError {
            throw PersistenceError.encodingFailed(error)
        } catch {
            throw PersistenceError.writeFailed(error)
        }
    }

    private func readJSON<T: Decodable>(from url: URL) throws -> T? {
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(T.self, from: data)
        } catch {
            // Corrupt file — silently discard
            try? fileManager.removeItem(at: url)
            return nil
        }
    }
}
