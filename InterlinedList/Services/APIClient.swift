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

    func messages(limit: Int = 50, offset: Int = 0, onlyMine: Bool = false, tag: String? = nil) async throws -> (messages: [Message], pagination: Pagination?) {
        var components = URLComponents(string: baseURL + "/api/messages")!
        components.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        if onlyMine {
            components.queryItems?.append(URLQueryItem(name: "onlyMine", value: "true"))
        }
        if let tag {
            components.queryItems?.append(URLQueryItem(name: "tag", value: tag))
        }
        let pathWithQuery = "/api/messages" + (components.percentEncodedQuery.map { "?" + $0 } ?? "")
        let response: MessagesResponse = try await get(pathWithQuery)
        return (response.messages, response.pagination)
    }

    func postMessage(content: String, publiclyVisible: Bool? = nil, parentId: String? = nil, tags: [String]? = nil, scheduledAt: String? = nil, imageUrls: [String]? = nil) async throws -> Message {
        struct Response: Decodable {
            let data: Message?
        }
        let body = CreateMessageBody(content: content, publiclyVisible: publiclyVisible, parentId: parentId, tags: tags, scheduledAt: scheduledAt, imageUrls: imageUrls)
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

    func editMessage(id: String, content: String, publiclyVisible: Bool?) async throws -> Message {
        struct Body: Encodable { let content: String; let publiclyVisible: Bool? }
        struct Response: Decodable { let data: Message? }
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let response: Response = try await put("/api/messages/\(encoded)", body: Body(content: content, publiclyVisible: publiclyVisible))
        guard let message = response.data else { throw APIError.noData }
        return message
    }

    struct DigResponse: Decodable { let digCount: Int; let dugByMe: Bool }

    func dig(messageId: String) async throws -> DigResponse {
        let encoded = messageId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? messageId
        struct Empty: Encodable {}
        return try await post("/api/messages/\(encoded)/dig", body: Empty())
    }

    func undig(messageId: String) async throws -> DigResponse {
        let encoded = messageId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? messageId
        guard let url = URL(string: baseURL + "/api/messages/\(encoded)/dig") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        try checkResponse(data: data, response: response)
        return try decoder.decode(DigResponse.self, from: data)
    }

    func replies(messageId: String, limit: Int = 50, offset: Int = 0) async throws -> [Message] {
        let encoded = messageId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? messageId
        let response: MessagesResponse = try await get("/api/messages/\(encoded)/replies?limit=\(limit)&offset=\(offset)")
        return response.messages
    }

    func scheduledMessages(range: String = "week") async throws -> [Message] {
        let response: MessagesResponse = try await get("/api/messages/scheduled?range=\(range)")
        return response.messages
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

    func createList(title: String, description: String?, isPublic: Bool) async throws -> UserList {
        struct Body: Encodable { let title: String; let description: String?; let isPublic: Bool }
        struct Response: Decodable { let list: UserList? }
        let response: Response = try await post("/api/lists", body: Body(title: title, description: description, isPublic: isPublic))
        guard let list = response.list else { throw APIError.noData }
        return list
    }

    func deleteList(id: String) async throws {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        guard let url = URL(string: baseURL + "/api/lists/\(encoded)") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        try checkResponse(data: data, response: response)
    }

    func toggleListItem(listId: String, itemId: String, checked: Bool) async throws -> ListItem {
        struct RowData: Encodable { let checked: Bool }
        struct Body: Encodable { let rowData: RowData }
        struct Response: Decodable { let row: ListItem? }
        let encodedList = listId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? listId
        let encodedItem = itemId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? itemId
        let response: Response = try await put("/api/lists/\(encodedList)/data/\(encodedItem)", body: Body(rowData: RowData(checked: checked)))
        guard let item = response.row else { throw APIError.noData }
        return item
    }

    func addListItem(listId: String, content: String) async throws -> ListItem {
        struct RowData: Encodable { let content: String }
        struct Body: Encodable { let rowData: RowData }
        struct Response: Decodable { let row: ListItem? }
        let encoded = listId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? listId
        let response: Response = try await post("/api/lists/\(encoded)/data", body: Body(rowData: RowData(content: content)))
        guard let item = response.row else { throw APIError.noData }
        return item
    }

    func deleteListItem(listId: String, itemId: String) async throws {
        let encodedList = listId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? listId
        let encodedItem = itemId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? itemId
        guard let url = URL(string: baseURL + "/api/lists/\(encodedList)/data/\(encodedItem)") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        try checkResponse(data: data, response: response)
    }

    // MARK: - Documents

    func documents() async throws -> [Document] {
        let response: DocumentsResponse = try await get("/api/documents")
        return response.documents
    }

    func createDocument(title: String, content: String?, isPublic: Bool, folderId: String?) async throws -> Document {
        struct Body: Encodable { let title: String; let content: String?; let isPublic: Bool; let folderId: String? }
        struct Response: Decodable { let document: Document? }
        let response: Response = try await post("/api/documents", body: Body(title: title, content: content, isPublic: isPublic, folderId: folderId))
        guard let doc = response.document else { throw APIError.noData }
        return doc
    }

    func updateDocument(id: String, title: String, content: String?, isPublic: Bool) async throws -> Document {
        struct Body: Encodable { let title: String; let content: String?; let isPublic: Bool }
        struct Response: Decodable { let document: Document? }
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let response: Response = try await patch("/api/documents/\(encoded)", body: Body(title: title, content: content, isPublic: isPublic))
        guard let doc = response.document else { throw APIError.noData }
        return doc
    }

    func deleteDocument(id: String) async throws {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        guard let url = URL(string: baseURL + "/api/documents/\(encoded)") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        try checkResponse(data: data, response: response)
    }

    func documentFolders() async throws -> [DocumentFolder] {
        let response: DocumentFoldersResponse = try await get("/api/documents/folders")
        return response.folders
    }

    func createDocumentFolder(name: String, parentId: String?) async throws -> DocumentFolder {
        struct Body: Encodable { let name: String; let parentId: String? }
        struct Response: Decodable { let folder: DocumentFolder? }
        let response: Response = try await post("/api/documents/folders", body: Body(name: name, parentId: parentId))
        guard let folder = response.folder else { throw APIError.noData }
        return folder
    }

    // MARK: - Image upload

    func uploadImage(data: Data, mimeType: String) async throws -> String {
        guard let url = URL(string: baseURL + "/api/messages/images/upload") else { throw APIError.invalidURL }
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        var body = Data()
        let ext = mimeType == "image/png" ? "png" : "jpg"
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"upload.\(ext)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        let (responseData, response) = try await session.data(for: request)
        try checkResponse(data: responseData, response: response)
        struct UploadResponse: Decodable { let url: String }
        return try decoder.decode(UploadResponse.self, from: responseData).url
    }

    // MARK: - People

    func publicMessages(username: String, limit: Int = 50, offset: Int = 0) async throws -> (messages: [Message], pagination: Pagination?) {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let response: MessagesResponse = try await get("/api/user/\(encoded)/messages?limit=\(limit)&offset=\(offset)")
        return (response.messages, response.pagination)
    }

    func publicLists(username: String) async throws -> [UserList] {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let response: ListsResponse = try await get("/api/users/\(encoded)/lists")
        return response.lists
    }

    // MARK: - Notifications

    func notifications() async throws -> NotificationsResponse {
        return try await get("/api/notifications?scope=tray")
    }

    func markNotificationRead(id: String) async throws {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        struct Empty: Encodable {}
        struct OkResponse: Decodable { let ok: Bool }
        let _: OkResponse = try await put("/api/notifications/\(encoded)/read", body: Empty())
    }

    func markAllNotificationsRead() async throws {
        struct Empty: Encodable {}
        struct OkResponse: Decodable { let ok: Bool; let updated: Int? }
        let _: OkResponse = try await post("/api/notifications/mark-all-read", body: Empty())
    }

    // MARK: - Follow

    func followUser(userId: String) async throws -> FollowStatus {
        let encoded = userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userId
        struct Empty: Encodable {}
        return try await post("/api/follow/\(encoded)", body: Empty())
    }

    func unfollowUser(userId: String) async throws {
        let encoded = userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userId
        guard let url = URL(string: baseURL + "/api/follow/\(encoded)") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        try checkResponse(data: data, response: response)
    }

    func followStatus(userId: String) async throws -> FollowStatus {
        let encoded = userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userId
        return try await get("/api/follow/\(encoded)/status")
    }

    func followCounts(userId: String) async throws -> FollowCounts {
        let encoded = userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userId
        return try await get("/api/follow/\(encoded)/counts")
    }

    func followRequests() async throws -> [FollowRequest] {
        let response: FollowRequestsResponse = try await get("/api/follow/requests")
        return response.requests
    }

    func approveFollowRequest(userId: String) async throws {
        let encoded = userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userId
        struct Empty: Encodable {}
        struct OkResponse: Decodable { let ok: Bool? }
        let _: OkResponse = try await post("/api/follow/\(encoded)/approve", body: Empty())
    }

    func rejectFollowRequest(userId: String) async throws {
        let encoded = userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userId
        struct Empty: Encodable {}
        struct OkResponse: Decodable { let ok: Bool? }
        let _: OkResponse = try await post("/api/follow/\(encoded)/reject", body: Empty())
    }

    // MARK: - Profile

    func updateProfile(displayName: String?, bio: String?, defaultVisibility: Bool?) async throws -> User {
        struct Body: Encodable { let displayName: String?; let bio: String?; let defaultVisibility: Bool? }
        struct WrappedResponse: Decodable { let user: User? }
        let body = Body(displayName: displayName, bio: bio, defaultVisibility: defaultVisibility)
        let wrapped: WrappedResponse = try await post("/api/user/update", body: body)
        if let user = wrapped.user { return user }
        return try await currentUser()
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

    private func put<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = bearerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await session.data(for: request)
        try checkResponse(data: data, response: response)
        return try decoder.decode(T.self, from: data)
    }

    private func patch<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = bearerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try encoder.encode(body)
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
