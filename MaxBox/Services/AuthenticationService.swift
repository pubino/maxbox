import Foundation
import AppKit

enum AuthError: Error, LocalizedError {
    case noClientId
    case invalidResponse
    case tokenExchangeFailed(String)
    case notAuthenticated
    case refreshFailed

    var errorDescription: String? {
        switch self {
        case .noClientId: return "OAuth Client ID not configured"
        case .invalidResponse: return "Invalid authentication response"
        case .tokenExchangeFailed(let reason): return "Token exchange failed: \(reason)"
        case .notAuthenticated: return "Not authenticated. Please sign in."
        case .refreshFailed: return "Failed to refresh access token"
        }
    }
}

protocol AuthenticationServiceProtocol {
    var isAuthenticated: Bool { get }
    func signIn() async throws -> Account
    func signOut(account: Account) async throws
    func refreshTokenIfNeeded(account: Account) async throws -> Account
    func getValidAccessToken(for account: Account) async throws -> String
}

final class AuthenticationService: AuthenticationServiceProtocol {
    // These must be set from GCP OAuth2 credentials
    // See GCP_SETUP.md for registration instructions
    static let clientId = ProcessInfo.processInfo.environment["MAXBOX_GMAIL_CLIENT_ID"] ?? ""
    static let clientSecret = ProcessInfo.processInfo.environment["MAXBOX_GMAIL_CLIENT_SECRET"] ?? ""

    static let scopes = [
        "openid",
        "email",
        "profile",
        "https://www.googleapis.com/auth/gmail.readonly",
        "https://www.googleapis.com/auth/gmail.modify",
        "https://www.googleapis.com/auth/gmail.compose",
        "https://www.googleapis.com/auth/gmail.labels"
    ]

    private let tokenURL = "https://oauth2.googleapis.com/token"
    private let authURL = "https://accounts.google.com/o/oauth2/v2/auth"
    private let userInfoURL = "https://www.googleapis.com/oauth2/v2/userinfo"

    private let keychainService: KeychainServiceProtocol

    private(set) var isAuthenticated: Bool = false

    init(keychainService: KeychainServiceProtocol = KeychainService()) {
        self.keychainService = keychainService
    }

    func signIn() async throws -> Account {
        guard !Self.clientId.isEmpty else {
            throw AuthError.noClientId
        }

        let (code, redirectURI) = try await requestAuthorizationCode()
        let tokenResponse = try await exchangeCodeForTokens(code: code, redirectURI: redirectURI)
        let userInfo = try await fetchUserInfo(accessToken: tokenResponse.accessToken)

        let account = Account(
            id: userInfo.id,
            email: userInfo.email,
            displayName: userInfo.name ?? userInfo.email,
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            tokenExpiry: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
        )

        // Store tokens in keychain
        try keychainService.save(key: "access_token_\(account.id)", value: tokenResponse.accessToken)
        if let refresh = tokenResponse.refreshToken {
            try keychainService.save(key: "refresh_token_\(account.id)", value: refresh)
        }

        isAuthenticated = true
        return account
    }

    func signOut(account: Account) async throws {
        try keychainService.delete(key: "access_token_\(account.id)")
        try keychainService.delete(key: "refresh_token_\(account.id)")
        isAuthenticated = false
    }

    func refreshTokenIfNeeded(account: Account) async throws -> Account {
        guard account.isTokenExpired else { return account }

        guard let refreshToken = account.refreshToken ?? (try? keychainService.read(key: "refresh_token_\(account.id)")) else {
            throw AuthError.notAuthenticated
        }

        let params = [
            "client_id": Self.clientId,
            "client_secret": Self.clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]

        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.httpBody = params.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let (data, _) = try await URLSession.shared.data(for: request)
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

        var updatedAccount = account
        updatedAccount.accessToken = tokenResponse.accessToken
        updatedAccount.tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))

        try keychainService.save(key: "access_token_\(updatedAccount.id)", value: tokenResponse.accessToken)

        return updatedAccount
    }

    func getValidAccessToken(for account: Account) async throws -> String {
        let refreshed = try await refreshTokenIfNeeded(account: account)
        guard let token = refreshed.accessToken else {
            throw AuthError.notAuthenticated
        }
        return token
    }

    // MARK: - Private

    private func requestAuthorizationCode() async throws -> (code: String, redirectURI: String) {
        let server = LoopbackAuthServer()
        let port = try server.start()
        let redirectURI = "http://127.0.0.1:\(port)"

        let scopeString = Self.scopes.joined(separator: " ")
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        let authURLString = "\(authURL)?client_id=\(Self.clientId)&redirect_uri=\(redirectURI)&response_type=code&scope=\(scopeString)&access_type=offline&prompt=consent"

        guard let url = URL(string: authURLString) else {
            server.stop()
            throw AuthError.invalidResponse
        }

        NSWorkspace.shared.open(url)

        do {
            let code = try await server.waitForCallback()
            server.stop()
            return (code, redirectURI)
        } catch {
            server.stop()
            throw error
        }
    }

    private func exchangeCodeForTokens(code: String, redirectURI: String) async throws -> TokenResponse {
        let params = [
            "client_id": Self.clientId,
            "client_secret": Self.clientSecret,
            "code": code,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ]

        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.httpBody = params.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw AuthError.tokenExchangeFailed(body)
        }

        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw AuthError.tokenExchangeFailed("Decode failed: \(error.localizedDescription)\nResponse: \(body)")
        }
    }

    private func fetchUserInfo(accessToken: String) async throws -> UserInfo {
        var request = URLRequest(url: URL(string: userInfoURL)!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw AuthError.tokenExchangeFailed("UserInfo failed: \(body)")
        }

        do {
            return try JSONDecoder().decode(UserInfo.self, from: data)
        } catch {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw AuthError.tokenExchangeFailed("UserInfo decode failed: \(error.localizedDescription)\nResponse: \(body)")
        }
    }
}

// MARK: - Response Types

struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let tokenType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

struct UserInfo: Decodable {
    let id: String
    let email: String
    let name: String?
}

// MARK: - Loopback OAuth Server (POSIX sockets)

private final class LoopbackAuthServer: @unchecked Sendable {
    private var serverFD: Int32 = -1
    private var assignedPort: UInt16 = 0

    func start() throws -> UInt16 {
        serverFD = socket(AF_INET, SOCK_STREAM, 0)
        guard serverFD >= 0 else { throw AuthError.invalidResponse }

        var reuse: Int32 = 1
        setsockopt(serverFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(serverFD)
            serverFD = -1
            throw AuthError.invalidResponse
        }

        guard listen(serverFD, 1) == 0 else {
            Darwin.close(serverFD)
            serverFD = -1
            throw AuthError.invalidResponse
        }

        // Read back the OS-assigned port
        var boundAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &boundAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(serverFD, $0, &addrLen)
            }
        }
        assignedPort = UInt16(bigEndian: boundAddr.sin_port)
        return assignedPort
    }

    func waitForCallback() async throws -> String {
        let fd = serverFD
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var clientAddr = sockaddr_in()
                var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                let clientFD = withUnsafeMutablePointer(to: &clientAddr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        accept(fd, $0, &clientLen)
                    }
                }
                guard clientFD >= 0 else {
                    continuation.resume(throwing: AuthError.invalidResponse)
                    return
                }

                var buffer = [UInt8](repeating: 0, count: 65536)
                let bytesRead = recv(clientFD, &buffer, buffer.count, 0)
                guard bytesRead > 0 else {
                    Darwin.close(clientFD)
                    continuation.resume(throwing: AuthError.invalidResponse)
                    return
                }

                let request = String(bytes: buffer[0..<bytesRead], encoding: .utf8) ?? ""

                // Parse: GET /?code=AUTH_CODE&scope=... HTTP/1.1
                guard let pathString = request.split(separator: " ").dropFirst().first,
                      let components = URLComponents(string: String(pathString)),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                    let errorParam = URLComponents(
                        string: String(request.split(separator: " ").dropFirst().first ?? "")
                    )?.queryItems?.first(where: { $0.name == "error" })?.value
                    self.sendResponse(to: clientFD, success: false, message: errorParam)
                    Darwin.close(clientFD)
                    continuation.resume(throwing: AuthError.tokenExchangeFailed(errorParam ?? "No authorization code received"))
                    return
                }

                self.sendResponse(to: clientFD, success: true, message: nil)
                Darwin.close(clientFD)
                continuation.resume(returning: code)
            }
        }
    }

    private func sendResponse(to fd: Int32, success: Bool, message: String?) {
        let body: String
        if success {
            body = "<html><body style=\"font-family:-apple-system,sans-serif;text-align:center;padding:60px\"><h1>Signed in to MaxBox</h1><p>You can close this tab and return to MaxBox.</p></body></html>"
        } else {
            let escaped = (message ?? "Unknown error")
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
            body = "<html><body style=\"font-family:-apple-system,sans-serif;text-align:center;padding:60px\"><h1>Authentication Failed</h1><p>\(escaped)</p></body></html>"
        }
        let header = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n"
        let response = Array((header + body).utf8)
        _ = send(fd, response, response.count, 0)
    }

    func stop() {
        if serverFD >= 0 {
            Darwin.close(serverFD)
            serverFD = -1
        }
    }
}
