import Foundation
@_exported import MoneybookCore

public struct APIError: LocalizedError {
    public var status: Int
    public var message: String
    public init(status: Int, message: String) { self.status = status; self.message = message }
    public var errorDescription: String? { status == 0 ? message : "\(message) (HTTP \(status))" }
}

/// Thin REST client for the Moneybook server (docs/API.md). Shared by the Mac and iPhone apps.
/// `token` is the API token or a device session from `login` ("s_…"); empty for the open sign-in endpoints.
public struct APIClient: Sendable {
    public let baseURL: URL
    public let token: String

    public init?(server: String, token: String) {
        var s = server.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if !s.isEmpty && !s.contains("://") { s = "https://" + s }
        guard !s.isEmpty, let url = URL(string: s), url.host != nil else { return nil }
        baseURL = url
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 15
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    // MARK: Core request

    public func data(_ method: String, _ path: String, query: [URLQueryItem] = [], json: [String: Any]? = nil,
              body: Data? = nil, contentType: String? = nil) async throws -> Data {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        if !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let json {
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if let body {
            req.httpBody = body
            req.setValue(contentType ?? "application/octet-stream", forHTTPHeaderField: "Content-Type")
        }
        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await Self.session.data(for: req)
        } catch {
            throw APIError(status: 0, message: (error as? URLError)?.localizedDescription ?? error.localizedDescription)
        }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let msg = obj?["error"] as? String ?? (status == 401 ? "Unauthorized: check the API token" : "Request failed")
            throw APIError(status: status, message: msg)
        }
        return data
    }

    public func decode<T: Decodable>(_ type: T.Type, _ method: String, _ path: String, query: [URLQueryItem] = [], json: [String: Any]? = nil) async throws -> T {
        let d = try await data(method, path, query: query, json: json)
        do {
            return try JSONDecoder().decode(T.self, from: d)
        } catch {
            throw APIError(status: 0, message: "Unexpected response from server: \(error.localizedDescription)")
        }
    }

    // MARK: Endpoints

    public func health() async throws {
        _ = try await data("GET", "api/health")
    }

    public struct AuthStatus: Decodable, Sendable {
        public var hasPassword: Bool
        public var email: String?
    }
    public func authStatus() async throws -> AuthStatus {
        try await decode(AuthStatus.self, "GET", "api/auth/status")
    }
    /// Email + password sign-in; returns a device session token.
    public func login(email: String, password: String) async throws -> String {
        struct R: Decodable { var session: String }
        return try await decode(R.self, "POST", "api/auth/login", json: ["email": email, "password": password]).session
    }
    /// Sets or changes the email + password login. `current` isn't needed when signed in with the API token.
    public func setPassword(email: String, password: String, current: String?) async throws {
        var body: [String: Any] = ["email": email, "password": password]
        if let current { body["current"] = current }
        _ = try await data("PUT", "api/auth/password", json: body)
    }
    public func logoutAll() async throws {
        _ = try await data("POST", "api/auth/logout-all")
    }
    /// Everything on the server as JSON (the web app's Backup → Export).
    public func exportAll() async throws -> Data {
        try await data("GET", "api/sync", query: [URLQueryItem(name: "since", value: "0")])
    }
    public func logout() async throws {
        _ = try await data("POST", "api/auth/logout")
    }

    public func sync(since: Int64) async throws -> SyncResponse {
        try await decode(SyncResponse.self, "GET", "api/sync", query: [URLQueryItem(name: "since", value: String(since))])
    }

    public func patchSettings(_ patch: [String: String]) async throws -> [String: String] {
        try await decode([String: String].self, "PATCH", "api/settings", json: patch)
    }

    public func createTransaction(_ body: [String: Any]) async throws -> Transaction {
        try await decode(Transaction.self, "POST", "api/transactions", json: body)
    }
    public func updateTransaction(_ id: String, _ body: [String: Any]) async throws -> Transaction {
        try await decode(Transaction.self, "PATCH", "api/transactions/\(id)", json: body)
    }
    public func deleteTransaction(_ id: String) async throws {
        _ = try await data("DELETE", "api/transactions/\(id)")
    }
    public func uploadReceipt(_ id: String, data image: Data, mimeType: String) async throws -> Transaction {
        let d = try await data("POST", "api/transactions/\(id)/receipt", body: image, contentType: mimeType)
        return try JSONDecoder().decode(Transaction.self, from: d)
    }
    public func deleteReceipt(_ id: String) async throws {
        _ = try await data("DELETE", "api/transactions/\(id)/receipt")
    }
    /// The `receipt` key is `receipts/<file>`, served at `/api/receipts/<file>`.
    public func receiptData(_ key: String) async throws -> Data {
        try await data("GET", "api/" + key)
    }

    public func createAccount(_ body: [String: Any]) async throws -> Account { try await decode(Account.self, "POST", "api/accounts", json: body) }
    public func updateAccount(_ id: String, _ body: [String: Any]) async throws -> Account { try await decode(Account.self, "PATCH", "api/accounts/\(id)", json: body) }
    public func deleteAccount(_ id: String) async throws { _ = try await data("DELETE", "api/accounts/\(id)") }

    public func createGroup(_ body: [String: Any]) async throws -> AccountGroup { try await decode(AccountGroup.self, "POST", "api/account-groups", json: body) }
    public func updateGroup(_ id: String, _ body: [String: Any]) async throws -> AccountGroup { try await decode(AccountGroup.self, "PATCH", "api/account-groups/\(id)", json: body) }
    public func deleteGroup(_ id: String) async throws { _ = try await data("DELETE", "api/account-groups/\(id)") }

    public func createCategory(_ body: [String: Any]) async throws -> MoneybookCore.Category { try await decode(MoneybookCore.Category.self, "POST", "api/categories", json: body) }
    public func updateCategory(_ id: String, _ body: [String: Any]) async throws -> MoneybookCore.Category { try await decode(MoneybookCore.Category.self, "PATCH", "api/categories/\(id)", json: body) }
    public func deleteCategory(_ id: String) async throws { _ = try await data("DELETE", "api/categories/\(id)") }

    /// `categoryId == nil` sets the Total budget; `month == nil` applies to every month; amount 0 removes.
    public func putBudget(categoryId: String?, month: String?, amount: Double) async throws -> Budget {
        var body: [String: Any] = ["amount": amount, "month": month ?? NSNull()]
        if let categoryId { body["category_id"] = categoryId } else { body["category"] = "Total" }
        return try await decode(Budget.self, "PUT", "api/budgets", json: body)
    }
    public func deleteBudget(_ id: String) async throws { _ = try await data("DELETE", "api/budgets/\(id)") }
}
