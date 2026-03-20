import Foundation
import AuthenticationServices

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
    static let redirectURI = "com.maxbox.MaxBox:/oauth2callback"

    static let scopes = [
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

        let code = try await requestAuthorizationCode()
        let tokenResponse = try await exchangeCodeForTokens(code: code)
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

    @MainActor
    private func requestAuthorizationCode() async throws -> String {
        let scopeString = Self.scopes.joined(separator: " ")
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        let authURLString = "\(authURL)?client_id=\(Self.clientId)&redirect_uri=\(Self.redirectURI)&response_type=code&scope=\(scopeString)&access_type=offline&prompt=consent"

        guard let url = URL(string: authURLString) else {
            throw AuthError.invalidResponse
        }

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "com.maxbox.MaxBox"
            ) { callbackURL, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let callbackURL = callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: AuthError.invalidResponse)
                    return
                }

                continuation.resume(returning: code)
            }

            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = NSApplication.shared.windows.first.flatMap { window in
                PresentationContextProvider(anchor: window)
            }
            session.start()
        }
    }

    private func exchangeCodeForTokens(code: String) async throws -> TokenResponse {
        let params = [
            "client_id": Self.clientId,
            "client_secret": Self.clientSecret,
            "code": code,
            "grant_type": "authorization_code",
            "redirect_uri": Self.redirectURI
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

        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private func fetchUserInfo(accessToken: String) async throws -> UserInfo {
        var request = URLRequest(url: URL(string: userInfoURL)!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(UserInfo.self, from: data)
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

// MARK: - Presentation Context

final class PresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    let anchor: NSWindow

    init(anchor: NSWindow) {
        self.anchor = anchor
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }
}
