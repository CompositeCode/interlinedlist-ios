//
//  APIClient.swift
//  InterlinedList
//

import Foundation

enum APIError: Error {
    case invalidURL
    case noData
    case decoding(Error)
    case server(String)
    case status(Int)
    case network(Error)
}

final class APIClient {
    static let shared = APIClient()
    private let baseURL: String
    private let session: URLSession
    private(set) var bearerToken: String?

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    /// Encoder that keeps camelCase keys (for APIs that expect camelCase in the request body, e.g. POST /api/messages).
    private let camelCaseEncoder: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()

    init(baseURL: String? = nil, session: URLSession = .shared) {
        let defaultBase = "https://interlinedlist.com"
        let plistOverride = (Bundle.main.infoDictionary?["ILAPIBaseURL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = (plistOverride?.isEmpty == false ? plistOverride : nil) ?? baseURL ?? defaultBase
        self.baseURL = resolved.hasSuffix("/") ? String(resolved.dropLast()) : resolved
        self.session = session
    }

    func setBearerToken(_ token: String?) {
        bearerToken = token
    }

    // MARK: - Auth

    func login(email: String, password: String) async throws -> String {
        struct Body: Encodable {
            let email: String
            let password: String
        }
        struct Response: Decodable {
            let token: String
        }
        let response: Response = try await post("/api/auth/sync-token", body: Body(email: email, password: password), authenticated: false)
        return response.token
    }

    func currentUser() async throws -> User {
        struct Response: Decodable {
            let user: User
        }
        let response: Response = try await get("/api/user")
        return response.user
    }

    func register(email: String, username: String, password: String, displayName: String?) async throws {
        struct Body: Encodable {
            let email: String
            let username: String
            let password: String
            let displayName: String?
        }
        struct Response: Decodable {
            let message: String?
            let user: User?
        }
        let _: Response = try await post("/api/auth/register", body: Body(email: email, username: username, password: password, displayName: displayName), authenticated: false)
    }

    // MARK: - Messages

    func messages(limit: Int = 50, offset: Int = 0, onlyMine: Bool = false) async throws -> (messages: [Message], pagination: Pagination?) {
        var components = URLComponents(string: baseURL + "/api/messages")!
        components.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        if onlyMine {
            components.queryItems?.append(URLQueryItem(name: "onlyMine", value: "true"))
        }
        let pathWithQuery = "/api/messages" + (components.percentEncodedQuery.map { "?" + $0 } ?? "")
        let response: MessagesResponse = try await get(pathWithQuery)
        return (response.messages, response.pagination)
    }

    func postMessage(content: String, publiclyVisible: Bool? = nil, parentId: String? = nil) async throws -> Message {
        struct Response: Decodable {
            let data: Message?
        }
        let body = CreateMessageBody(content: content, publiclyVisible: publiclyVisible, parentId: parentId)
        // Backend expects camelCase (publiclyVisible, parentId); snake_case would send publicly_visible and be ignored.
        guard let url = URL(string: baseURL + "/api/messages") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = bearerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try camelCaseEncoder.encode(body)
        let (data, response) = try await session.data(for: request)
        try checkResponse(data: data, response: response)
        let decoded: Response = try decoder.decode(Response.self, from: data)
        guard let message = decoded.data else { throw APIError.noData }
        return message
    }

    // MARK: - Lists

    func listsAndFolders() async throws -> (folders: [ListFolder], lists: [UserList]) {
        // Folders are supplementary — silently ignore non-auth failures (endpoint may not exist).
        let folders: [ListFolder]
        do {
            let response: FoldersResponse = try await get("/api/folders")
            folders = response.folders
        } catch APIError.status(401) {
            throw APIError.status(401)
        } catch {
            folders = []
        }

        // Lists are required — propagate errors so the UI can surface them.
        let listsResponse: ListsResponse = try await get("/api/lists")
        return (folders, listsResponse.lists)
    }

    func listItems(listId: String) async throws -> [ListItem] {
        let encoded = listId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? listId
        let response: ListItemsResponse = try await get("/api/lists/\(encoded)/items")
        return response.items
    }

    func deleteMessage(id: String) async throws {
        var request = URLRequest(url: URL(string: baseURL + "/api/messages/" + id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)!)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = bearerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 401 {
            throw APIError.status(401)
        }
        if http.statusCode >= 400 {
            if http.statusCode == 403 {
                throw APIError.server("You can only delete your own messages.")
            }
            throw APIError.status(http.statusCode)
        }
    }

    // MARK: - Private helpers


    private func get<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = bearerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        try checkResponse(data: data, response: response)
        return try decoder.decode(T.self, from: data)
    }

    private func post<T: Decodable, B: Encodable>(_ path: String, body: B, authenticated: Bool = true) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated, let token = bearerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await session.data(for: request)
        try checkResponse(data: data, response: response)
        return try decoder.decode(T.self, from: data)
    }

    private func checkResponse(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 401 {
            throw APIError.status(401)
        }
        if http.statusCode >= 400 {
            if let err = try? decoder.decode(ErrorResponse.self, from: data) {
                throw APIError.server(err.error)
            }
            throw APIError.status(http.statusCode)
        }
    }
}

private struct ErrorResponse: Decodable {
    let error: String
}
