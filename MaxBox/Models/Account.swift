import Foundation

struct Account: Identifiable, Codable, Hashable {
    let id: String
    var email: String
    var displayName: String
    var accessToken: String?
    var refreshToken: String?
    var tokenExpiry: Date?
    var isActive: Bool = true

    var isAuthenticated: Bool {
        accessToken != nil && refreshToken != nil
    }

    var isTokenExpired: Bool {
        guard let expiry = tokenExpiry else { return true }
        return Date() >= expiry
    }
}
