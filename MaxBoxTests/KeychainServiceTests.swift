import XCTest
@testable import MaxBox

final class MockKeychainServiceTests: XCTestCase {

    func testSaveAndRead() throws {
        let keychain = MockKeychainService()
        try keychain.save(key: "test-key", value: "test-value")
        let result = try keychain.read(key: "test-key")
        XCTAssertEqual(result, "test-value")
        XCTAssertEqual(keychain.saveCallCount, 1)
        XCTAssertEqual(keychain.readCallCount, 1)
    }

    func testRead_notFound() throws {
        let keychain = MockKeychainService()
        let result = try keychain.read(key: "nonexistent")
        XCTAssertNil(result)
    }

    func testDelete() throws {
        let keychain = MockKeychainService()
        try keychain.save(key: "key", value: "value")
        try keychain.delete(key: "key")
        let result = try keychain.read(key: "key")
        XCTAssertNil(result)
        XCTAssertEqual(keychain.deleteCallCount, 1)
    }

    func testSaveOverwrite() throws {
        let keychain = MockKeychainService()
        try keychain.save(key: "key", value: "v1")
        try keychain.save(key: "key", value: "v2")
        let result = try keychain.read(key: "key")
        XCTAssertEqual(result, "v2")
    }

    func testSaveError() {
        let keychain = MockKeychainService()
        keychain.saveError = KeychainError.unexpectedStatus(-1)
        XCTAssertThrowsError(try keychain.save(key: "k", value: "v"))
    }

    func testReadError() {
        let keychain = MockKeychainService()
        keychain.readError = KeychainError.unexpectedStatus(-1)
        XCTAssertThrowsError(try keychain.read(key: "k"))
    }
}
