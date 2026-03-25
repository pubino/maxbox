import Foundation
import os.log

private let logger = Logger(subsystem: "com.maxbox.MaxBox", category: "Compose")

@MainActor
final class ComposeViewModel: ObservableObject {
    @Published var to = "" { didSet { markDirtyIfNeeded() } }
    @Published var cc = "" { didSet { markDirtyIfNeeded() } }
    @Published var bcc = "" { didSet { markDirtyIfNeeded() } }
    @Published var subject = "" { didSet { markDirtyIfNeeded() } }
    @Published var body = "" { didSet { markDirtyIfNeeded() } }
    @Published var isSending = false
    @Published var errorMessage: String?
    @Published var didSend = false
    @Published var showCloseConfirmation = false
    @Published private(set) var draftSavedAt: Date?

    private(set) var draftId: String?
    private(set) var isDirty = false
    var accessToken: String?

    /// The Gmail message ID of the source draft (used to remove it from the list on discard).
    var originalMessageId: String?

    /// Closure to obtain a fresh access token, refreshing if needed (H5).
    var tokenRefresher: (() async throws -> String)?

    /// Account ID for local draft storage (C3).
    var accountId: String?

    private let gmailService: GmailAPIServiceProtocol
    let persistenceService: PersistenceServiceProtocol
    private var autoSaveTimer: Timer?
    private var suppressDirty = false
    private static let autoSaveInterval: TimeInterval = 10 // H4: reduced from 30s

    /// ID of the local draft fallback when remote save fails.
    private(set) var localDraftId: UUID?

    init(gmailService: GmailAPIServiceProtocol? = nil, persistenceService: PersistenceServiceProtocol? = nil) {
        self.gmailService = gmailService ?? GmailAPIService()
        self.persistenceService = persistenceService ?? PersistenceService()
    }

    var isValid: Bool {
        !to.trimmingCharacters(in: .whitespaces).isEmpty &&
        !subject.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var hasContent: Bool {
        !to.trimmingCharacters(in: .whitespaces).isEmpty ||
        !subject.trimmingCharacters(in: .whitespaces).isEmpty ||
        !body.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Auto-Save

    func startAutoSave() {
        stopAutoSave()
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: Self.autoSaveInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.autoSaveTick()
            }
        }
    }

    func stopAutoSave() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
    }

    private func autoSaveTick() async {
        guard isDirty, hasContent else { return }
        await saveDraft()
    }

    // MARK: - Token Resolution (H5)

    /// Obtain the best available access token, refreshing if needed.
    private func resolveToken() async -> String? {
        if let refresher = tokenRefresher {
            do {
                let fresh = try await refresher()
                accessToken = fresh
                return fresh
            } catch {
                logger.warning("Token refresh failed: \(error.localizedDescription)")
            }
        }
        return accessToken
    }

    // MARK: - Draft Operations

    func saveDraft() async {
        guard let token = await resolveToken() else {
            // No token available — fall back to local draft (C3)
            saveLocalDraft()
            return
        }

        do {
            if let existingId = draftId {
                try await gmailService.updateDraft(
                    accessToken: token,
                    draftId: existingId,
                    to: to,
                    cc: cc.isEmpty ? nil : cc,
                    bcc: bcc.isEmpty ? nil : bcc,
                    subject: subject,
                    body: body
                )
            } else {
                let newId = try await gmailService.createDraft(
                    accessToken: token,
                    to: to,
                    cc: cc.isEmpty ? nil : cc,
                    bcc: bcc.isEmpty ? nil : bcc,
                    subject: subject,
                    body: body
                )
                draftId = newId
            }
            isDirty = false
            draftSavedAt = Date()
            // Remote save succeeded — clean up local fallback if present
            cleanupLocalDraft()
        } catch {
            // Remote save failed — fall back to local draft (C3)
            logger.warning("Remote draft save failed: \(error.localizedDescription). Saving locally.")
            saveLocalDraft()
        }
    }

    func discardDraft() async {
        stopAutoSave()
        if let token = await resolveToken(), let id = draftId {
            do {
                try await gmailService.deleteDraft(accessToken: token, draftId: id)
                draftId = nil // M3: only nil after successful delete
                // Notify message list to remove the draft from view
                if let messageId = originalMessageId {
                    NotificationCenter.default.post(
                        name: .draftDiscarded,
                        object: nil,
                        userInfo: ["messageId": messageId]
                    )
                }
            } catch {
                // M3: Keep draftId so caller knows remote draft still exists
                logger.warning("Failed to discard remote draft \(id): \(error.localizedDescription)")
            }
        }
        cleanupLocalDraft()
        isDirty = false
    }

    /// Load an existing draft message into the compose fields.
    func loadDraft(accessToken: String, messageId: String) async {
        do {
            let message = try await gmailService.getMessage(accessToken: accessToken, messageId: messageId)
            let fetchedDraftId = try? await gmailService.getDraftId(accessToken: accessToken, messageId: messageId)

            suppressDirty = true
            to = message.to.joined(separator: ", ")
            cc = message.cc.joined(separator: ", ")
            subject = message.subject
            body = message.body
            self.draftId = fetchedDraftId
            isDirty = false
            draftSavedAt = nil
            suppressDirty = false
        } catch {
            errorMessage = "Failed to load draft"
        }
    }

    // MARK: - Local Draft Fallback (C3)

    private func saveLocalDraft() {
        let draft = LocalDraft(
            to: to, cc: cc, bcc: bcc,
            subject: subject, body: body,
            accountId: accountId,
            remoteDraftId: draftId
        )
        do {
            if let existingId = localDraftId {
                try persistenceService.deleteLocalDraft(id: existingId)
            }
            try persistenceService.saveLocalDraft(draft)
            localDraftId = draft.id
            isDirty = false
            draftSavedAt = draft.savedAt
        } catch {
            logger.error("Local draft save also failed: \(error.localizedDescription)")
        }
    }

    private func cleanupLocalDraft() {
        guard let id = localDraftId else { return }
        try? persistenceService.deleteLocalDraft(id: id)
        localDraftId = nil
    }

    // MARK: - Reply / Forward

    func populateFromContext(_ ctx: ComposeContext) {
        suppressDirty = true

        switch ctx.mode {
        case .reply:
            to = ctx.originalFrom
            subject = ctx.originalSubject.hasPrefix("Re:") ? ctx.originalSubject : "Re: \(ctx.originalSubject)"
        case .replyAll:
            to = ctx.originalFrom
            let others = ctx.originalTo + ctx.originalCc
            cc = others.joined(separator: ", ")
            subject = ctx.originalSubject.hasPrefix("Re:") ? ctx.originalSubject : "Re: \(ctx.originalSubject)"
        case .forward:
            subject = ctx.originalSubject.hasPrefix("Fwd:") ? ctx.originalSubject : "Fwd: \(ctx.originalSubject)"
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        let dateStr = dateFormatter.string(from: ctx.originalDate)

        let quotedHeader = "\n\nOn \(dateStr), \(ctx.originalFrom) wrote:\n"
        let quotedBody: String
        if let html = ctx.originalBodyHTML, !html.isEmpty {
            // Strip HTML tags for plain-text quoting
            let stripped = html
                .replacingOccurrences(of: "<br[^>]*>", with: "\n", options: .regularExpression)
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
            quotedBody = stripped.split(separator: "\n", omittingEmptySubsequences: false)
                .map { "> \($0)" }
                .joined(separator: "\n")
        } else {
            quotedBody = ctx.originalBody.split(separator: "\n", omittingEmptySubsequences: false)
                .map { "> \($0)" }
                .joined(separator: "\n")
        }

        body = quotedHeader + quotedBody

        isDirty = false
        suppressDirty = false
    }

    // MARK: - Send

    func send(accessToken: String) async {
        guard isValid else {
            errorMessage = "Please fill in the To and Subject fields."
            return
        }

        isSending = true
        errorMessage = nil

        // H5: Use fresh token if available
        let token: String
        if let refresher = tokenRefresher, let fresh = try? await refresher() {
            self.accessToken = fresh
            token = fresh
        } else {
            token = accessToken
        }

        do {
            try await gmailService.sendMessage(
                accessToken: token,
                to: to,
                subject: subject,
                body: body,
                cc: cc.isEmpty ? nil : cc,
                bcc: bcc.isEmpty ? nil : bcc
            )

            // Clean up draft after successful send
            if let id = draftId {
                try? await gmailService.deleteDraft(accessToken: token, draftId: id)
                draftId = nil
            }

            stopAutoSave()
            cleanupLocalDraft()
            didSend = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isSending = false
    }

    // MARK: - Close Flow

    func requestClose() -> Bool {
        if isDirty && hasContent {
            showCloseConfirmation = true
            return false
        }
        stopAutoSave()
        return true
    }

    // MARK: - Reset

    func reset() {
        suppressDirty = true
        to = ""
        cc = ""
        bcc = ""
        subject = ""
        body = ""
        errorMessage = nil
        didSend = false
        draftId = nil
        isDirty = false
        draftSavedAt = nil
        suppressDirty = false
    }

    // MARK: - Private

    private func markDirtyIfNeeded() {
        guard !suppressDirty else { return }
        isDirty = true
    }
}
