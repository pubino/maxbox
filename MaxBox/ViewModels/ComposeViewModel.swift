import Foundation

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

    private let gmailService: GmailAPIServiceProtocol
    private var autoSaveTimer: Timer?
    private var suppressDirty = false
    private static let autoSaveInterval: TimeInterval = 30

    init(gmailService: GmailAPIServiceProtocol? = nil) {
        self.gmailService = gmailService ?? GmailAPIService()
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
        guard isDirty, hasContent, accessToken != nil else { return }
        await saveDraft()
    }

    // MARK: - Draft Operations

    func saveDraft() async {
        guard let token = accessToken else { return }

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
        } catch {
            // Auto-save failures are silent; user can still save manually
        }
    }

    func discardDraft() async {
        stopAutoSave()
        if let token = accessToken, let id = draftId {
            try? await gmailService.deleteDraft(accessToken: token, draftId: id)
        }
        draftId = nil
    }

    // MARK: - Send

    func send(accessToken: String) async {
        guard isValid else {
            errorMessage = "Please fill in the To and Subject fields."
            return
        }

        isSending = true
        errorMessage = nil

        do {
            try await gmailService.sendMessage(
                accessToken: accessToken,
                to: to,
                subject: subject,
                body: body,
                cc: cc.isEmpty ? nil : cc,
                bcc: bcc.isEmpty ? nil : bcc
            )

            // Clean up draft after successful send
            if let id = draftId {
                try? await gmailService.deleteDraft(accessToken: accessToken, draftId: id)
                draftId = nil
            }

            stopAutoSave()
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
