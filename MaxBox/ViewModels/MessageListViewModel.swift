import Foundation
import Combine
import os.log

private let logger = Logger(subsystem: "com.maxbox.MaxBox", category: "MessageList")

extension Notification.Name {
    static let draftDiscarded = Notification.Name("draftDiscarded")
}

struct CachedMailbox {
    var messages: [Message]
    var fetchedAt: Date
    var nextPageToken: String?
    var hasMorePages: Bool
}

@MainActor
final class MessageListViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var selectedMessageId: String?
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var errorMessage: String?
    @Published var searchQuery = ""
    @Published var filterUnread = false

    private let gmailService: GmailAPIServiceProtocol
    let activityManager: ActivityManager
    let persistenceService: PersistenceServiceProtocol
    private var nextPageToken: String?
    private var hasMorePages = true
    private var currentSelection: SidebarSelection?
    private var refreshTask: Task<Void, Never>?
    private var draftDiscardObserver: Any?

    private(set) var cache: [SidebarSelection: CachedMailbox] = [:]

    static let cacheTTL: TimeInterval = 300 // 5 minutes
    static let diskCacheTTL: TimeInterval = 3600 // 1 hour

    var filteredMessages: [Message] {
        if filterUnread {
            return messages.filter { !$0.isRead }
        }
        return messages
    }

    var selectedMessage: Message? {
        messages.first { $0.id == selectedMessageId }
    }

    init(
        gmailService: GmailAPIServiceProtocol? = nil,
        activityManager: ActivityManager? = nil,
        persistenceService: PersistenceServiceProtocol? = nil
    ) {
        self.gmailService = gmailService ?? GmailAPIService()
        self.activityManager = activityManager ?? .shared
        self.persistenceService = persistenceService ?? PersistenceService()

        draftDiscardObserver = NotificationCenter.default.addObserver(
            forName: .draftDiscarded, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self,
                  let messageId = notification.userInfo?["messageId"] as? String else { return }
            self.removeMessage(id: messageId)
            // Invalidate all DRAFT cache entries so next switch reloads fresh
            for key in self.cache.keys {
                if key.mailboxType == .drafts {
                    self.cache.removeValue(forKey: key)
                }
            }
        }
    }

    // MARK: - Cache-aware entry point

    /// Switch to a mailbox: restore cache instantly, then sync in background.
    /// For search queries, always fetch fresh (no cache).
    func switchMailbox(
        selection: SidebarSelection,
        tokens: [(accountId: String, token: String)],
        forceRefresh: Bool = false
    ) async {
        // Cancel any in-flight refresh for a previous selection
        refreshTask?.cancel()
        refreshTask = nil
        currentSelection = selection

        let isSearch = !searchQuery.isEmpty
        let labelId = selection.mailboxType.gmailLabelId

        // Restore cache if available and not searching
        if !isSearch, !forceRefresh, let cached = cache[selection] {
            messages = cached.messages
            nextPageToken = cached.nextPageToken
            hasMorePages = cached.hasMorePages

            // Background differential sync
            isRefreshing = true
            let task = Task {
                await differentialSync(selection: selection, tokens: tokens, labelId: labelId)
                if !Task.isCancelled {
                    isRefreshing = false
                }
            }
            refreshTask = task
            await task.value
            return
        }

        // Check disk cache before full fetch
        if !isSearch, !forceRefresh,
           let diskCache = try? persistenceService.loadMailboxCache(for: selection),
           diskCache.age < Self.diskCacheTTL {
            let restored = diskCache.toCachedMailbox()
            cache[selection] = restored
            messages = restored.messages
            nextPageToken = restored.nextPageToken
            hasMorePages = restored.hasMorePages

            // Background differential sync
            isRefreshing = true
            let task = Task {
                await differentialSync(selection: selection, tokens: tokens, labelId: labelId)
                if !Task.isCancelled {
                    isRefreshing = false
                }
            }
            refreshTask = task
            await task.value
            return
        }

        // No cache — full progressive load with spinner
        messages = []
        isLoading = true
        errorMessage = nil
        await performFetch(selection: selection, tokens: tokens, labelId: labelId, query: nil)
        isLoading = false
    }

    // MARK: - Legacy shims (used by loadMore, tests)

    func loadMessages(accessToken: String, labelId: String, query: String? = nil) async {
        await loadMessages(accountId: nil, accessToken: accessToken, labelId: labelId, query: query)
    }

    func loadMessages(accountId: String?, accessToken: String, labelId: String, query: String? = nil) async {
        isLoading = true
        errorMessage = nil
        nextPageToken = nil
        hasMorePages = true

        do {
            let searchQ = buildQuery(query)
            let response = try await gmailService.listMessages(
                accessToken: accessToken,
                labelId: labelId,
                query: searchQ,
                pageToken: nil,
                maxResults: 50
            )

            nextPageToken = response.nextPageToken
            hasMorePages = response.nextPageToken != nil

            guard let refs = response.messages else {
                messages = []
                isLoading = false
                return
            }

            var loadedMessages: [Message] = []
            for ref in refs {
                do {
                    let message = try await gmailService.getMessage(
                        accessToken: accessToken,
                        messageId: ref.id
                    )
                    var msg = message
                    msg.accountId = accountId
                    loadedMessages.append(msg)
                } catch {
                    // Skip individual message failures
                }
            }

            messages = loadedMessages
        } catch {
            errorMessage = error.localizedDescription
            messages = []
        }

        isLoading = false
    }

    func loadMessagesFromAllAccounts(tokens: [(accountId: String, token: String)], labelId: String, query: String? = nil) async {
        isLoading = true
        errorMessage = nil
        nextPageToken = nil
        hasMorePages = false

        let result = await fetchFromAllAccounts(tokens: tokens, labelId: labelId, query: query)
        messages = result.messages
        if messages.isEmpty, let err = result.error {
            errorMessage = err
        }

        isLoading = false
    }

    func loadMoreMessages(accessToken: String, labelId: String) async {
        guard hasMorePages, let pageToken = nextPageToken, !isLoading else { return }

        isLoading = true
        let activityId = activityManager.start("Loading more messages")

        do {
            let response = try await gmailService.listMessages(
                accessToken: accessToken,
                labelId: labelId,
                query: buildQuery(nil),
                pageToken: pageToken,
                maxResults: 50
            )

            nextPageToken = response.nextPageToken
            hasMorePages = response.nextPageToken != nil

            guard let refs = response.messages else {
                isLoading = false
                activityManager.complete(activityId)
                return
            }

            activityManager.update(activityId, current: 0, total: refs.count,
                                   detail: "Fetching \(refs.count) messages")

            for (index, ref) in refs.enumerated() {
                do {
                    let message = try await gmailService.getMessage(
                        accessToken: accessToken,
                        messageId: ref.id
                    )
                    messages.append(message)
                    activityManager.update(activityId, current: index + 1)
                } catch {
                    // Skip
                }
            }

            // Update cache with appended messages
            if let sel = currentSelection {
                let cached = CachedMailbox(
                    messages: messages,
                    fetchedAt: Date(),
                    nextPageToken: nextPageToken,
                    hasMorePages: hasMorePages
                )
                cache[sel] = cached
                persistCacheToDisk(cached, for: sel)
            }

            activityManager.complete(activityId)
        } catch {
            errorMessage = error.localizedDescription
            activityManager.fail(activityId, error: error.localizedDescription)
        }

        isLoading = false
    }

    // MARK: - Message mutations

    func markAsRead(accessToken: String, messageId: String) async {
        do {
            try await gmailService.modifyMessage(
                accessToken: accessToken,
                messageId: messageId,
                addLabels: [],
                removeLabels: ["UNREAD"]
            )
            updateMessageInPlace(messageId: messageId) { $0.isRead = true }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleStar(accessToken: String, messageId: String) async {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }

        let isStarred = messages[index].isStarred
        do {
            try await gmailService.modifyMessage(
                accessToken: accessToken,
                messageId: messageId,
                addLabels: isStarred ? [] : ["STARRED"],
                removeLabels: isStarred ? ["STARRED"] : []
            )
            updateMessageInPlace(messageId: messageId) { $0.isStarred = !isStarred }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Remove a message from the active list and all cache entries immediately.
    func removeMessage(id: String) {
        messages.removeAll { $0.id == id }
        for key in cache.keys {
            cache[key]?.messages.removeAll { $0.id == id }
        }
        if let sel = currentSelection {
            if let cached = cache[sel] {
                persistCacheToDisk(cached, for: sel)
            }
        }
    }

    // MARK: - Cache management

    func invalidateCache(for selection: SidebarSelection? = nil) {
        if let selection = selection {
            cache.removeValue(forKey: selection)
        } else {
            cache.removeAll()
        }
    }

    // MARK: - Full fetch (cache miss / force refresh)

    private func performFetch(
        selection: SidebarSelection,
        tokens: [(accountId: String, token: String)],
        labelId: String,
        query: String?
    ) async {
        let mailboxName = selection.mailboxType.displayName
        let activityId = activityManager.start("Loading \(mailboxName)")

        errorMessage = nil
        nextPageToken = nil
        hasMorePages = true

        switch selection {
        case .allAccounts:
            if tokens.count <= 1, let first = tokens.first {
                await fetchSingleAccountProgressive(
                    accountId: first.accountId, token: first.token,
                    labelId: labelId, query: query, activityId: activityId
                )
            } else {
                await fetchAllAccountsProgressive(
                    tokens: tokens, labelId: labelId,
                    query: query, activityId: activityId
                )
            }
        case .account(_, let accountId):
            guard let token = tokens.first(where: { $0.accountId == accountId })?.token else {
                activityManager.complete(activityId)
                return
            }
            await fetchSingleAccountProgressive(
                accountId: accountId, token: token,
                labelId: labelId, query: query, activityId: activityId
            )
        }

        // Store in cache (only for non-search fetches)
        if query == nil, !Task.isCancelled {
            let cached = CachedMailbox(
                messages: messages,
                fetchedAt: Date(),
                nextPageToken: nextPageToken,
                hasMorePages: hasMorePages
            )
            cache[selection] = cached
            persistCacheToDisk(cached, for: selection)
        }

        if !Task.isCancelled {
            activityManager.complete(activityId)
        }
    }

    // MARK: - Differential sync (cache hit background refresh)

    /// Compare fresh message IDs from the API against cached IDs.
    /// Only fetch details for new messages; remove stale ones.
    private func differentialSync(
        selection: SidebarSelection,
        tokens: [(accountId: String, token: String)],
        labelId: String
    ) async {
        guard !Task.isCancelled else { return }

        let mailboxName = selection.mailboxType.displayName
        let activityId = activityManager.start("Checking \(mailboxName)")

        // Collect fresh message refs from all relevant accounts
        var freshRefs: [(id: String, accountId: String, token: String)] = []

        switch selection {
        case .allAccounts:
            for (accountId, token) in tokens {
                if Task.isCancelled { activityManager.complete(activityId); return }
                do {
                    let maxResults = tokens.count > 1 ? 25 : 50
                    let response = try await gmailService.listMessages(
                        accessToken: token, labelId: labelId,
                        query: nil, pageToken: nil, maxResults: maxResults
                    )
                    for ref in (response.messages ?? []) {
                        freshRefs.append((ref.id, accountId, token))
                    }
                } catch {
                    // On error, silently skip — cached data is still showing
                    activityManager.complete(activityId)
                    return
                }
            }
        case .account(_, let accountId):
            guard let token = tokens.first(where: { $0.accountId == accountId })?.token else {
                activityManager.complete(activityId)
                return
            }
            do {
                let response = try await gmailService.listMessages(
                    accessToken: token, labelId: labelId,
                    query: nil, pageToken: nil, maxResults: 50
                )
                for ref in (response.messages ?? []) {
                    freshRefs.append((ref.id, accountId, token))
                }
            } catch {
                activityManager.complete(activityId)
                return
            }
        }

        if Task.isCancelled { activityManager.complete(activityId); return }

        let freshIds = Set(freshRefs.map(\.id))
        let cachedIds = Set(messages.map(\.id))

        // Nothing changed — done
        if freshIds == cachedIds {
            activityManager.complete(activityId)
            return
        }

        let newIds = freshIds.subtracting(cachedIds)
        let removedIds = cachedIds.subtracting(freshIds)

        // Remove stale messages
        if !removedIds.isEmpty {
            messages.removeAll { removedIds.contains($0.id) }
        }

        // Fetch only new messages
        if !newIds.isEmpty {
            let refsToFetch = freshRefs.filter { newIds.contains($0.id) }
            activityManager.update(activityId, current: 0, total: refsToFetch.count,
                                   detail: "Fetching \(refsToFetch.count) new messages")

            for (index, ref) in refsToFetch.enumerated() {
                if Task.isCancelled { break }
                do {
                    let message = try await gmailService.getMessage(
                        accessToken: ref.token, messageId: ref.id
                    )
                    var msg = message
                    msg.accountId = ref.accountId
                    messages.append(msg)
                    activityManager.update(activityId, current: index + 1)
                } catch {
                    // Skip individual failures
                }
            }
        }

        // Re-sort by date
        messages.sort { $0.date > $1.date }

        // Update cache
        if !Task.isCancelled {
            let cached = CachedMailbox(
                messages: messages,
                fetchedAt: Date(),
                nextPageToken: nextPageToken,
                hasMorePages: hasMorePages
            )
            cache[selection] = cached
            persistCacheToDisk(cached, for: selection)
        }

        activityManager.complete(activityId)
    }

    // MARK: - Progressive fetching

    /// Fetch messages for a single account, appending each to `messages` as it arrives.
    private func fetchSingleAccountProgressive(
        accountId: String, token: String,
        labelId: String, query: String?,
        activityId: UUID
    ) async {
        do {
            let searchQ = buildQuery(query)
            let response = try await gmailService.listMessages(
                accessToken: token,
                labelId: labelId,
                query: searchQ,
                pageToken: nil,
                maxResults: 50
            )

            if Task.isCancelled { return }

            nextPageToken = response.nextPageToken
            hasMorePages = response.nextPageToken != nil

            guard let refs = response.messages else {
                messages = []
                return
            }

            activityManager.update(activityId, current: 0, total: refs.count,
                                   detail: "Fetching \(refs.count) messages")

            for (index, ref) in refs.enumerated() {
                if Task.isCancelled { return }
                do {
                    let message = try await gmailService.getMessage(
                        accessToken: token,
                        messageId: ref.id
                    )
                    var msg = message
                    msg.accountId = accountId
                    if !Task.isCancelled {
                        messages.append(msg)
                        activityManager.update(activityId, current: index + 1)
                    }
                } catch {
                    // Skip
                }
            }
        } catch {
            if !Task.isCancelled {
                errorMessage = error.localizedDescription
                messages = []
            }
        }
    }

    /// Progressive multi-account fetch: collect refs from all accounts, then fetch details.
    private func fetchAllAccountsProgressive(
        tokens: [(accountId: String, token: String)],
        labelId: String, query: String?,
        activityId: UUID
    ) async {
        let searchQ = buildQuery(query)
        var allRefs: [(ref: MessageRef, accountId: String, token: String)] = []
        var firstError: String?

        // Phase 1: collect all refs
        for (accountId, token) in tokens {
            if Task.isCancelled { return }
            do {
                let response = try await gmailService.listMessages(
                    accessToken: token, labelId: labelId,
                    query: searchQ, pageToken: nil, maxResults: 25
                )
                for ref in (response.messages ?? []) {
                    allRefs.append((ref, accountId, token))
                }
            } catch {
                if firstError == nil { firstError = error.localizedDescription }
            }
        }

        if Task.isCancelled { return }

        activityManager.update(activityId, current: 0, total: allRefs.count,
                               detail: "Fetching \(allRefs.count) messages")

        // Phase 2: fetch details progressively
        for (index, item) in allRefs.enumerated() {
            if Task.isCancelled { return }
            do {
                let message = try await gmailService.getMessage(
                    accessToken: item.token, messageId: item.ref.id
                )
                var msg = message
                msg.accountId = item.accountId
                if !Task.isCancelled {
                    messages.append(msg)
                    activityManager.update(activityId, current: index + 1)
                }
            } catch {
                // Skip
            }
        }

        if !Task.isCancelled {
            messages.sort { $0.date > $1.date }
            hasMorePages = false
            if messages.isEmpty, let err = firstError {
                errorMessage = err
            }
        }
    }

    // MARK: - Legacy multi-account fetch (for loadMessagesFromAllAccounts shim)

    private func fetchFromAllAccounts(
        tokens: [(accountId: String, token: String)],
        labelId: String,
        query: String?
    ) async -> (messages: [Message], error: String?) {
        let searchQ = buildQuery(query)
        var allMessages: [Message] = []
        var firstError: String?

        for (accountId, token) in tokens {
            if Task.isCancelled { return (allMessages, firstError) }
            do {
                let response = try await gmailService.listMessages(
                    accessToken: token,
                    labelId: labelId,
                    query: searchQ,
                    pageToken: nil,
                    maxResults: 25
                )

                guard let refs = response.messages else { continue }

                for ref in refs {
                    if Task.isCancelled { return (allMessages, firstError) }
                    do {
                        let message = try await gmailService.getMessage(
                            accessToken: token,
                            messageId: ref.id
                        )
                        var msg = message
                        msg.accountId = accountId
                        allMessages.append(msg)
                    } catch {
                        // Skip
                    }
                }
            } catch {
                if firstError == nil {
                    firstError = error.localizedDescription
                }
            }
        }

        allMessages.sort { $0.date > $1.date }
        return (allMessages, firstError)
    }

    /// Update a message both in the active list and in all cache entries.
    private func updateMessageInPlace(messageId: String, mutate: (inout Message) -> Void) {
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            mutate(&messages[index])
        }
        for key in cache.keys {
            if let index = cache[key]?.messages.firstIndex(where: { $0.id == messageId }) {
                mutate(&cache[key]!.messages[index])
            }
        }
    }

    private func buildQuery(_ additionalQuery: String?) -> String? {
        var parts: [String] = []
        if !searchQuery.isEmpty {
            parts.append(searchQuery)
        }
        if let additional = additionalQuery, !additional.isEmpty {
            parts.append(additional)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// L4: Maximum number of in-memory cache entries to prevent unbounded growth.
    static let maxCacheEntries = 20

    private func persistCacheToDisk(_ cached: CachedMailbox, for selection: SidebarSelection) {
        let persistable = PersistableMailboxCache(from: cached)
        do {
            try persistenceService.saveMailboxCache(persistable, for: selection)
        } catch {
            logger.error("Failed to persist cache for \(selection.cacheKey): \(error.localizedDescription)")
            errorMessage = "Could not save message cache — \(error.localizedDescription)"
        }

        // L4: Evict oldest entries if cache grows too large
        if cache.count > Self.maxCacheEntries {
            let sorted = cache.sorted { $0.value.fetchedAt < $1.value.fetchedAt }
            let toRemove = sorted.prefix(cache.count - Self.maxCacheEntries)
            for (key, _) in toRemove {
                cache.removeValue(forKey: key)
            }
        }
    }
}
