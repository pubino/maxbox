import XCTest
@testable import MaxBox

@MainActor
final class ComposeViewModelTests: XCTestCase {
    var mockGmail: MockGmailAPIService!
    var mockPersistence: MockPersistenceService!
    var sut: ComposeViewModel!

    override func setUp() {
        super.setUp()
        mockGmail = MockGmailAPIService()
        mockPersistence = MockPersistenceService()
        sut = ComposeViewModel(gmailService: mockGmail, persistenceService: mockPersistence)
    }

    override func tearDown() {
        sut.stopAutoSave()
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialState() {
        XCTAssertEqual(sut.to, "")
        XCTAssertEqual(sut.cc, "")
        XCTAssertEqual(sut.bcc, "")
        XCTAssertEqual(sut.subject, "")
        XCTAssertEqual(sut.body, "")
        XCTAssertFalse(sut.isSending)
        XCTAssertNil(sut.errorMessage)
        XCTAssertFalse(sut.didSend)
        XCTAssertFalse(sut.isDirty)
        XCTAssertNil(sut.draftId)
        XCTAssertFalse(sut.showCloseConfirmation)
    }

    // MARK: - Validation

    func testIsValid_emptyFields_returnsFalse() {
        XCTAssertFalse(sut.isValid)
    }

    func testIsValid_onlyTo_returnsFalse() {
        sut.to = "alice@example.com"
        XCTAssertFalse(sut.isValid)
    }

    func testIsValid_onlySubject_returnsFalse() {
        sut.subject = "Test"
        XCTAssertFalse(sut.isValid)
    }

    func testIsValid_toAndSubject_returnsTrue() {
        sut.to = "alice@example.com"
        sut.subject = "Test Subject"
        XCTAssertTrue(sut.isValid)
    }

    func testIsValid_whitespaceOnly_returnsFalse() {
        sut.to = "   "
        sut.subject = "   "
        XCTAssertFalse(sut.isValid)
    }

    // MARK: - Dirty Tracking

    func testIsDirty_tracksFieldChanges() {
        XCTAssertFalse(sut.isDirty)

        sut.to = "alice@example.com"
        XCTAssertTrue(sut.isDirty)
    }

    func testIsDirty_tracksSubjectChange() {
        sut.subject = "Hello"
        XCTAssertTrue(sut.isDirty)
    }

    func testIsDirty_tracksBodyChange() {
        sut.body = "Some content"
        XCTAssertTrue(sut.isDirty)
    }

    func testIsDirty_tracksCcChange() {
        sut.cc = "bob@example.com"
        XCTAssertTrue(sut.isDirty)
    }

    func testIsDirty_tracksBccChange() {
        sut.bcc = "secret@example.com"
        XCTAssertTrue(sut.isDirty)
    }

    func testReset_clearsDirty() {
        sut.to = "alice@example.com"
        XCTAssertTrue(sut.isDirty)

        sut.reset()
        XCTAssertFalse(sut.isDirty)
    }

    func testReset_doesNotSetDirty() {
        sut.reset()
        XCTAssertFalse(sut.isDirty)
    }

    // MARK: - Send

    func testSend_success() async {
        sut.to = "alice@example.com"
        sut.subject = "Hello"
        sut.body = "Test body"
        sut.cc = "bob@example.com"

        await sut.send(accessToken: "token")

        XCTAssertTrue(sut.didSend)
        XCTAssertFalse(sut.isSending)
        XCTAssertNil(sut.errorMessage)
        XCTAssertEqual(mockGmail.sendMessageCallCount, 1)
        XCTAssertEqual(mockGmail.lastSendTo, "alice@example.com")
        XCTAssertEqual(mockGmail.lastSendSubject, "Hello")
        XCTAssertEqual(mockGmail.lastSendBody, "Test body")
        XCTAssertEqual(mockGmail.lastSendCc, "bob@example.com")
    }

    func testSend_withBcc() async {
        sut.to = "alice@example.com"
        sut.subject = "Hello"
        sut.bcc = "hidden@example.com"

        await sut.send(accessToken: "token")

        XCTAssertTrue(sut.didSend)
        XCTAssertEqual(mockGmail.lastSendBcc, "hidden@example.com")
    }

    func testSend_emptyCc_sendsNil() async {
        sut.to = "alice@example.com"
        sut.subject = "Hello"

        await sut.send(accessToken: "token")

        XCTAssertTrue(sut.didSend)
        XCTAssertNil(mockGmail.lastSendCc)
        XCTAssertNil(mockGmail.lastSendBcc)
    }

    func testSend_invalidForm_setsError() async {
        await sut.send(accessToken: "token")

        XCTAssertFalse(sut.didSend)
        XCTAssertNotNil(sut.errorMessage)
        XCTAssertEqual(mockGmail.sendMessageCallCount, 0)
    }

    func testSend_apiFailure() async {
        sut.to = "alice@example.com"
        sut.subject = "Hello"
        mockGmail.sendMessageError = GmailAPIError.requestFailed(500, "Server Error")

        await sut.send(accessToken: "token")

        XCTAssertFalse(sut.didSend)
        XCTAssertNotNil(sut.errorMessage)
        XCTAssertFalse(sut.isSending)
    }

    func testSend_deletesDraftAfterSend() async {
        // First save a draft to get a draftId
        sut.accessToken = "token"
        sut.to = "alice@example.com"
        sut.subject = "Hello"
        await sut.saveDraft()
        XCTAssertNotNil(sut.draftId)

        // Now send
        await sut.send(accessToken: "token")

        XCTAssertTrue(sut.didSend)
        XCTAssertEqual(mockGmail.deleteDraftCallCount, 1)
        XCTAssertNil(sut.draftId)
    }

    func testSend_noDraft_noDeleteCall() async {
        sut.to = "alice@example.com"
        sut.subject = "Hello"

        await sut.send(accessToken: "token")

        XCTAssertTrue(sut.didSend)
        XCTAssertEqual(mockGmail.deleteDraftCallCount, 0)
    }

    // MARK: - Save Draft

    func testSaveDraft_creates_whenNoDraftId() async {
        sut.accessToken = "token"
        sut.to = "alice@example.com"
        sut.subject = "Draft Subject"

        await sut.saveDraft()

        XCTAssertEqual(mockGmail.createDraftCallCount, 1)
        XCTAssertEqual(mockGmail.updateDraftCallCount, 0)
        XCTAssertEqual(sut.draftId, "mock-draft-id")
    }

    func testSaveDraft_updates_whenDraftIdExists() async {
        sut.accessToken = "token"
        sut.to = "alice@example.com"
        sut.subject = "Draft Subject"

        // First create
        await sut.saveDraft()
        XCTAssertEqual(mockGmail.createDraftCallCount, 1)

        // Modify and save again
        sut.subject = "Updated Subject"
        await sut.saveDraft()

        XCTAssertEqual(mockGmail.createDraftCallCount, 1)
        XCTAssertEqual(mockGmail.updateDraftCallCount, 1)
        XCTAssertEqual(mockGmail.lastDraftId, "mock-draft-id")
    }

    func testSaveDraft_setsDirtyFalse() async {
        sut.accessToken = "token"
        sut.to = "alice@example.com"
        XCTAssertTrue(sut.isDirty)

        await sut.saveDraft()

        XCTAssertFalse(sut.isDirty)
    }

    func testSaveDraft_setsDraftSavedAt() async {
        sut.accessToken = "token"
        sut.to = "alice@example.com"
        XCTAssertNil(sut.draftSavedAt)

        await sut.saveDraft()

        XCTAssertNotNil(sut.draftSavedAt)
    }

    func testSaveDraft_noAccessToken_savesLocally() async {
        sut.to = "alice@example.com"

        await sut.saveDraft()

        // C3: No remote call, but local draft should be saved
        XCTAssertEqual(mockGmail.createDraftCallCount, 0)
        XCTAssertEqual(mockPersistence.saveLocalDraftCallCount, 1)
        XCTAssertNotNil(sut.localDraftId)
        XCTAssertNotNil(sut.draftSavedAt)
    }

    func testSaveDraft_remoteFailure_fallsBackToLocal() async {
        sut.accessToken = "token"
        sut.to = "alice@example.com"
        mockGmail.createDraftResult = .failure(GmailAPIError.requestFailed(500, "Server Error"))

        await sut.saveDraft()

        // C3: Remote failed, local draft saved
        XCTAssertEqual(mockGmail.createDraftCallCount, 1)
        XCTAssertEqual(mockPersistence.saveLocalDraftCallCount, 1)
        XCTAssertNotNil(sut.localDraftId)
    }

    func testSaveDraft_remoteSuccess_cleansUpLocalDraft() async {
        // First save fails remotely, creating a local draft
        sut.accessToken = "token"
        sut.to = "alice@example.com"
        mockGmail.createDraftResult = .failure(GmailAPIError.requestFailed(500, "err"))
        await sut.saveDraft()
        XCTAssertNotNil(sut.localDraftId)

        // Now remote succeeds
        mockGmail.createDraftResult = .success("mock-draft-id")
        sut.to = "alice@example.com"
        await sut.saveDraft()

        // Local draft should be cleaned up
        XCTAssertEqual(mockPersistence.deleteLocalDraftCallCount, 1)
    }

    func testDiscardDraft_remoteFailure_keepsDraftId() async {
        sut.accessToken = "token"
        sut.to = "alice@example.com"
        await sut.saveDraft()
        XCTAssertNotNil(sut.draftId)

        // M3: Remote delete fails — draftId should be preserved
        mockGmail.deleteDraftError = GmailAPIError.requestFailed(500, "err")
        await sut.discardDraft()

        XCTAssertNotNil(sut.draftId) // M3: still set
    }

    // MARK: - Close Flow

    func testRequestClose_dirtyWithContent_showsConfirmation() {
        sut.to = "alice@example.com"
        XCTAssertTrue(sut.isDirty)
        XCTAssertTrue(sut.hasContent)

        let shouldDismiss = sut.requestClose()

        XCTAssertFalse(shouldDismiss)
        XCTAssertTrue(sut.showCloseConfirmation)
    }

    func testRequestClose_clean_dismissesDirectly() {
        let shouldDismiss = sut.requestClose()

        XCTAssertTrue(shouldDismiss)
        XCTAssertFalse(sut.showCloseConfirmation)
    }

    func testRequestClose_dirtyButNoContent_dismissesDirectly() {
        // Set to empty string after init doesn't count as content
        // But didSet will mark dirty — however hasContent is false
        // Actually setting to = "" triggers didSet but content is empty
        // Let's test: set to something, save draft (clears dirty), then set to empty
        sut.to = ""
        // isDirty is true because didSet fired, but hasContent is false
        let shouldDismiss = sut.requestClose()
        // isDirty is true but hasContent is false — should dismiss
        XCTAssertTrue(shouldDismiss)
        XCTAssertFalse(sut.showCloseConfirmation)
    }

    // MARK: - Discard Draft

    func testDiscardDraft_deletesDraftIfExists() async {
        sut.accessToken = "token"
        sut.to = "alice@example.com"
        await sut.saveDraft()
        XCTAssertNotNil(sut.draftId)

        await sut.discardDraft()

        XCTAssertEqual(mockGmail.deleteDraftCallCount, 1)
        XCTAssertNil(sut.draftId)
    }

    func testDiscardDraft_noDraftId_noApiCall() async {
        sut.accessToken = "token"
        XCTAssertNil(sut.draftId)

        await sut.discardDraft()

        XCTAssertEqual(mockGmail.deleteDraftCallCount, 0)
    }

    // MARK: - Reset

    func testReset() {
        sut.to = "alice@example.com"
        sut.cc = "bob@example.com"
        sut.bcc = "secret@example.com"
        sut.subject = "Hello"
        sut.body = "World"
        sut.errorMessage = "Some error"
        sut.didSend = true

        sut.reset()

        XCTAssertEqual(sut.to, "")
        XCTAssertEqual(sut.cc, "")
        XCTAssertEqual(sut.bcc, "")
        XCTAssertEqual(sut.subject, "")
        XCTAssertEqual(sut.body, "")
        XCTAssertNil(sut.errorMessage)
        XCTAssertFalse(sut.didSend)
        XCTAssertNil(sut.draftId)
        XCTAssertFalse(sut.isDirty)
    }

    // MARK: - hasContent

    func testHasContent_emptyFields_returnsFalse() {
        XCTAssertFalse(sut.hasContent)
    }

    func testHasContent_withTo_returnsTrue() {
        sut.to = "alice@example.com"
        XCTAssertTrue(sut.hasContent)
    }

    func testHasContent_withSubjectOnly_returnsTrue() {
        sut.subject = "Subject"
        XCTAssertTrue(sut.hasContent)
    }

    func testHasContent_withBodyOnly_returnsTrue() {
        sut.body = "Some text"
        XCTAssertTrue(sut.hasContent)
    }

    func testHasContent_whitespaceOnly_returnsFalse() {
        sut.to = "   "
        sut.subject = "   "
        sut.body = "   "
        XCTAssertFalse(sut.hasContent)
    }
}
