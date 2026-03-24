import Foundation
import os.log

private let logger = Logger(subsystem: "com.maxbox.MaxBox", category: "Persistence")

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

    func saveLocalDraft(_ draft: LocalDraft) throws
    func loadLocalDraft(id: UUID) throws -> LocalDraft?
    func deleteLocalDraft(id: UUID) throws
    func loadAllLocalDrafts() throws -> [LocalDraft]
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
        let expected = VersionedStore<[PersistableAccount]>.currentVersion
        if store.version > expected {
            // Future version — preserve file, return empty so we don't corrupt newer data
            logger.warning("Accounts file version \(store.version) is newer than expected \(expected); skipping load")
            return []
        }
        if store.version < expected {
            // Older version — migrate: current schema is compatible with v1 payload,
            // so re-save at current version. Extend with explicit migration steps as needed.
            logger.info("Migrating accounts from v\(store.version) to v\(expected)")
            try? writeJSON(VersionedStore(payload: store.payload), to: url)
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
        let expected = VersionedStore<PersistableMailboxCache>.currentVersion
        if store.version > expected {
            logger.warning("Cache version \(store.version) is newer than expected \(expected); skipping")
            return nil
        }
        if store.version < expected {
            logger.info("Migrating cache from v\(store.version) to v\(expected)")
            try? writeJSON(VersionedStore(payload: store.payload), to: url)
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

    // MARK: - Local Drafts (C3 fallback)

    private var draftsDirectory: URL {
        baseDirectory.appendingPathComponent("drafts")
    }

    func saveLocalDraft(_ draft: LocalDraft) throws {
        let url = draftsDirectory.appendingPathComponent("\(draft.id.uuidString).json")
        try writeJSON(draft, to: url)
    }

    func loadLocalDraft(id: UUID) throws -> LocalDraft? {
        let url = draftsDirectory.appendingPathComponent("\(id.uuidString).json")
        return try readJSON(from: url)
    }

    func deleteLocalDraft(id: UUID) throws {
        let url = draftsDirectory.appendingPathComponent("\(id.uuidString).json")
        try? fileManager.removeItem(at: url)
    }

    func loadAllLocalDrafts() throws -> [LocalDraft] {
        guard fileManager.fileExists(atPath: draftsDirectory.path) else { return [] }
        let files = try fileManager.contentsOfDirectory(at: draftsDirectory, includingPropertiesForKeys: nil)
        return files.compactMap { url -> LocalDraft? in
            guard url.pathExtension == "json" else { return nil }
            return try? readJSON(from: url)
        }
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
            // Corrupt file — back up before removing so data isn't permanently lost
            let backupURL = url.appendingPathExtension("bak")
            try? fileManager.removeItem(at: backupURL) // remove stale backup
            try? fileManager.copyItem(at: url, to: backupURL)
            try? fileManager.removeItem(at: url)
            logger.error("Corrupt file at \(url.lastPathComponent): \(error.localizedDescription). Backup saved to \(backupURL.lastPathComponent)")
            return nil
        }
    }
}
