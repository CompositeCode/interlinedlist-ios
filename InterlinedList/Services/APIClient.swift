//
//  APIClient.swift
//  InterlinedList
//

import Foundation
import os.log

private let apiLog = Logger(subsystem: "com.interlinedlist.app", category: "APIClient")

enum APIError: Error {
    case invalidURL
    case noData
    case decoding(Error)
    case server(String)
    case status(Int)
    case network(Error)
    /// 409 — the request conflicts with existing data (e.g. deleting a list
    /// property that still has row values without `?force=true`).
    case conflict(String)
}

enum ExportType: String, CaseIterable {
    case messages, lists, follows
}

final class APIClient {
    static let shared = APIClient()
    private let baseURL: String
    private let session: URLSessionProtocol
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

    init(baseURL: String? = nil, session: URLSessionProtocol = URLSession.shared) {
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

    // MARK: - Password reset

    func forgotPassword(email: String) async throws {
        struct Body: Encodable { let email: String }
        struct Response: Decodable { let message: String? }
        let _: Response = try await post("/api/auth/forgot-password", body: Body(email: email), authenticated: false)
    }

    func resetPassword(token: String, password: String) async throws {
        struct Body: Encodable { let token: String; let password: String }
        struct Response: Decodable { let message: String? }
        let _: Response = try await post("/api/auth/reset-password", body: Body(token: token, password: password), authenticated: false)
    }

    // MARK: - Email verification

    func sendVerificationEmail() async throws {
        struct Empty: Encodable {}
        struct Response: Decodable { let message: String? }
        let _: Response = try await post("/api/auth/send-verification-email", body: Empty())
    }

    func verifyEmail(token: String) async throws {
        struct Body: Encodable { let token: String }
        struct Response: Decodable { let message: String? }
        let _: Response = try await post("/api/auth/verify-email", body: Body(token: token), authenticated: false)
    }

    func verifyEmailChange(token: String) async throws {
        struct Body: Encodable { let token: String }
        struct Response: Decodable { let message: String? }
        let _: Response = try await post("/api/auth/verify-email-change", body: Body(token: token), authenticated: false)
    }

    // MARK: - Email change

    func requestEmailChange(newEmail: String, password: String) async throws {
        struct Body: Encodable { let newEmail: String; let password: String }
        struct Response: Decodable { let message: String? }
        let _: Response = try await postCamel("/api/user/change-email/request", body: Body(newEmail: newEmail, password: password))
    }

    // MARK: - Linked identities

    struct LinkedIdentity: Identifiable, Codable {
        let id: String
        let provider: String
        let providerUsername: String?
        let createdAt: String?

        /// Base provider name without any instance suffix (e.g. "mastodon:techhub.social" → "mastodon").
        var providerType: String { String(provider.prefix(while: { $0 != ":" })) }
    }

    func linkedIdentities() async throws -> [LinkedIdentity] {
        struct Response: Decodable { let identities: [LinkedIdentity]? }
        let response: Response = try await get("/api/user/identities")
        return response.identities ?? []
    }

    func unlinkIdentity(provider: String, providerId: String) async throws {
        struct Body: Encodable { let provider: String; let providerId: String }
        guard let url = URL(string: baseURL + "/api/user/identities") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try camelCaseEncoder.encode(Body(provider: provider, providerId: providerId))
        let (data, response) = try await session.data(for: request)
        try checkResponse(data: data, response: response)
    }

    func verifyIdentity(provider: String, providerId: String) async throws {
        struct Body: Encodable { let provider: String; let providerId: String }
        struct Response: Decodable { let ok: Bool? }
        let _: Response = try await postCamel("/api/user/identities/verify", body: Body(provider: provider, providerId: providerId))
    }

    // MARK: - OAuth configuration status

    struct OAuthConfigStatus: Decodable {
        let configured: Bool
        let redirectUri: String?
    }

    func linkedinStatus() async throws -> OAuthConfigStatus {
        return try await get("/api/auth/linkedin/status")
    }

    func twitterStatus() async throws -> OAuthConfigStatus {
        return try await get("/api/auth/twitter/status")
    }

    // MARK: - Avatar upload (Phase 3 — sister agent dependency)

    func uploadAvatar(data: Data, mimeType: String) async throws -> User {
        guard let url = URL(string: baseURL + "/api/user/avatar/upload") else { throw APIError.invalidURL }
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let ext = mimeType == "image/png" ? "png" : "jpg"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"avatar.\(ext)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        let (responseData, response) = try await session.data(for: request)
        try checkResponse(data: responseData, response: response)
        struct UploadResp: Decodable { let url: String? }
        if let avatarUrl = (try? decoder.decode(UploadResp.self, from: responseData))?.url {
            return try await applyAvatarUrl(avatarUrl)
        }
        return try await currentUser()
    }

    func setAvatarFromURL(_ avatarUrl: String) async throws -> User {
        struct Body: Encodable { let url: String }
        struct Response: Decodable { let url: String? }
        let resp: Response = try await post("/api/user/avatar/from-url", body: Body(url: avatarUrl))
        return try await applyAvatarUrl(resp.url ?? avatarUrl)
    }

    private func applyAvatarUrl(_ url: String) async throws -> User {
        struct Body: Encodable { let avatar: String }
        struct Resp: Decodable { let user: User? }
        let wrapped: Resp = try await post("/api/user/update", body: Body(avatar: url))
        if let user = wrapped.user { return user }
        return try await currentUser()
    }

    // MARK: - Organizations (Phase 3 — sister agent dependency)

    func userOrganizations() async throws -> [Organization] {
        struct Response: Decodable { let organizations: [Organization]? }
        let response: Response = try await get("/api/user/organizations")
        return response.organizations ?? []
    }

    // MARK: - Delete account (Phase 3 — sister agent dependency)

    func deleteAccount() async throws {
        struct Empty: Encodable {}
        struct Response: Decodable { let message: String? }
        let _: Response = try await post("/api/user/delete", body: Empty())
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

    /// Result of creating a message — the created message plus any cross-post
    /// outcomes the server reported (empty when cross-posting wasn't requested or
    /// the deployment doesn't echo results).
    struct PostMessageResult {
        let message: Message
        let crossPostResults: [CrossPostResult]
    }

    @discardableResult
    func postMessage(
        content: String,
        publiclyVisible: Bool? = nil,
        parentId: String? = nil,
        tags: [String]? = nil,
        scheduledAt: String? = nil,
        imageUrls: [String]? = nil,
        videoUrls: [String]? = nil,
        pushedMessageId: String? = nil,
        mastodonProviderIds: [String]? = nil,
        crossPostToBluesky: Bool? = nil,
        crossPostToLinkedIn: Bool? = nil,
        linkedInTargets: [LinkedInTarget]? = nil,
        linkedInLinkAsFirstComment: Bool? = nil,
        crossPostToTwitter: Bool? = nil,
        organizationId: String? = nil
    ) async throws -> PostMessageResult {
        let body = CreateMessageBody(
            content: content, publiclyVisible: publiclyVisible, parentId: parentId,
            tags: tags, scheduledAt: scheduledAt, imageUrls: imageUrls, videoUrls: videoUrls,
            pushedMessageId: pushedMessageId, mastodonProviderIds: mastodonProviderIds,
            crossPostToBluesky: crossPostToBluesky, crossPostToLinkedIn: crossPostToLinkedIn,
            linkedInTargets: linkedInTargets, linkedInLinkAsFirstComment: linkedInLinkAsFirstComment,
            crossPostToTwitter: crossPostToTwitter, scheduledCrossPostConfig: nil,
            organizationId: organizationId)
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
        let decoded: CreateMessageResponse = try decoder.decode(CreateMessageResponse.self, from: data)
        guard let message = decoded.data else { throw APIError.noData }
        return PostMessageResult(message: message, crossPostResults: decoded.crossPostResults ?? [])
    }

    /// Edit a scheduled (not-yet-published) message's send time and cross-post config.
    @discardableResult
    func patchScheduledMessage(id: String, scheduledAt: String, config: ScheduledCrossPostConfig?) async throws -> Message? {
        struct Body: Encodable {
            let scheduledAt: String
            let scheduledCrossPostConfig: ScheduledCrossPostConfig?
        }
        struct Response: Decodable { let data: Message? }
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        guard let url = URL(string: baseURL + "/api/messages/\(encoded)") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try camelCaseEncoder.encode(Body(scheduledAt: scheduledAt, scheduledCrossPostConfig: config))
        let (data, response) = try await session.data(for: request)
        try checkResponse(data: data, response: response)
        return (try? decoder.decode(Response.self, from: data))?.data
    }

    /// Fetch/refresh OpenGraph link-preview metadata for a message's links.
    @discardableResult
    func refreshMessageMetadata(messageId: String) async throws -> [MessageLinkPreview] {
        struct Response: Decodable {
            struct Meta: Decodable { let links: [MessageLinkPreview]? }
            let metadata: Meta?
        }
        let encoded = messageId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? messageId
        struct Empty: Encodable {}
        let response: Response = try await postCamel("/api/messages/\(encoded)/metadata", body: Empty())
        return response.metadata?.links ?? []
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
        let foldersResponse: FoldersResponse = try await get("/api/folders")
        let listsResponse: ListsResponse = try await get("/api/lists")
        return (foldersResponse.folders, listsResponse.lists)
    }

    func listItems(listId: String) async throws -> [ListItem] {
        let encoded = listId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? listId
        struct DataResponse: Decodable {
            let rows: [ListItem]?
            let items: [ListItem]?
        }
        let response: DataResponse = try await get("/api/lists/\(encoded)/data")
        return response.rows ?? response.items ?? []
    }

    func listSchema(listId: String) async throws -> [ListPropertyDef] {
        let encoded = listId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? listId
        let response: ListDetailResponse = try await get("/api/lists/\(encoded)")
        return response.data.properties
    }

    func createList(title: String, description: String?, isPublic: Bool) async throws -> UserList {
        struct Body: Encodable { let title: String; let description: String?; let isPublic: Bool }
        struct Response: Decodable { let list: UserList? }
        let response: Response = try await postCamel("/api/lists", body: Body(title: title, description: description, isPublic: isPublic))
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

    func updateRow(listId: String, itemId: String, key: String, value: JSONValue) async throws -> ListItem {
        struct Body: Encodable { let data: [String: JSONValue] }
        struct Response: Decodable { let row: ListItem? }
        let encodedList = listId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? listId
        let encodedItem = itemId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? itemId
        let response: Response = try await put("/api/lists/\(encodedList)/data/\(encodedItem)", body: Body(data: [key: value]))
        guard let item = response.row else { throw APIError.noData }
        return item
    }

    func addListItem(listId: String, rowData: [String: JSONValue]) async throws -> ListItem {
        struct Body: Encodable { let data: [String: JSONValue] }
        struct Response: Decodable { let row: ListItem? }
        let encoded = listId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? listId
        let response: Response = try await post("/api/lists/\(encoded)/data", body: Body(data: rowData))
        guard let item = response.row else { throw APIError.noData }
        return item
    }

    func updateItem(listId: String, itemId: String, rowData: [String: JSONValue]) async throws -> ListItem {
        struct Body: Encodable { let data: [String: JSONValue] }
        struct Response: Decodable { let row: ListItem? }
        let encodedList = listId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? listId
        let encodedItem = itemId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? itemId
        let response: Response = try await put("/api/lists/\(encodedList)/data/\(encodedItem)", body: Body(data: rowData))
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

    func documents(folderId: String? = nil) async throws -> [Document] {
        // `GET /api/documents` returns ONLY root-level documents (folderId is null) and
        // ignores any query string — passing `?folderId=` made every folder show the root
        // documents. Documents inside a folder must come from the folder-scoped endpoint.
        let path: String
        if let folderId, !folderId.isEmpty,
           let encoded = folderId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
            path = "/api/documents/folders/\(encoded)/documents"
        } else {
            path = "/api/documents"
        }
        let response: DocumentsResponse = try await get(path)
        return response.documents
    }

    func createDocument(title: String, content: String?, isPublic: Bool, folderId: String?) async throws -> Document {
        // The folder is chosen by the *path*, not a body field: `POST /api/documents` always
        // creates at root (it has no folderId field), so a document "created in a folder" via
        // that route silently lands at root. Post to the folder-scoped endpoint instead.
        // Bodies are camelCase (`isPublic`) — use postCamel or the flag is dropped server-side.
        struct Body: Encodable { let title: String; let content: String?; let isPublic: Bool }
        struct Response: Decodable { let document: Document? }
        let body = Body(title: title, content: content, isPublic: isPublic)
        let path: String
        if let folderId, !folderId.isEmpty,
           let encoded = folderId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
            path = "/api/documents/folders/\(encoded)/documents"
        } else {
            path = "/api/documents"
        }
        let response: Response = try await postCamel(path, body: body)
        guard let doc = response.document else { throw APIError.noData }
        return doc
    }

    func updateDocument(id: String, title: String, content: String?, isPublic: Bool, folderId: String? = nil) async throws -> Document {
        // PATCH is the only documents write that accepts `folderId` (to move between folders).
        // The body is camelCase (`folderId`, `isPublic`); patchCamel keeps it that way so the
        // server actually applies the move and visibility change. (Sending `folderId: nil`
        // omits the key, so this can move a doc *into* a folder but not back out to root.)
        struct Body: Encodable { let title: String; let content: String?; let isPublic: Bool; let folderId: String? }
        struct Response: Decodable { let document: Document? }
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let response: Response = try await patchCamel("/api/documents/\(encoded)", body: Body(title: title, content: content, isPublic: isPublic, folderId: folderId))
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
        // Body is camelCase (`parentId`); postCamel keeps a nested folder under its parent
        // instead of dropping `parent_id` and creating it at root.
        struct Body: Encodable { let name: String; let parentId: String? }
        struct Response: Decodable { let folder: DocumentFolder? }
        let response: Response = try await postCamel("/api/documents/folders", body: Body(name: name, parentId: parentId))
        guard let folder = response.folder else { throw APIError.noData }
        return folder
    }

    /// Soft-deletes a document folder. The server cascades the delete to any
    /// subfolders and documents inside it (`DELETE /api/documents/folders/{id}`).
    func deleteDocumentFolder(id: String) async throws {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        guard let url = URL(string: baseURL + "/api/documents/folders/\(encoded)") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        try checkResponse(data: data, response: response)
    }

    func searchDocuments(q: String, limit: Int = 20, offset: Int = 0) async throws -> ([Document], Pagination?) {
        let qEncoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        struct Response: Decodable { let documents: [Document]; let pagination: Pagination? }
        let response: Response = try await get("/api/documents/search?q=\(qEncoded)&limit=\(limit)&offset=\(offset)")
        return (response.documents, response.pagination)
    }

    func updateList(id: String, title: String?, description: String?, isPublic: Bool?) async throws -> UserList {
        struct Body: Encodable { let title: String?; let description: String?; let isPublic: Bool? }
        struct Response: Decodable { let list: UserList? }
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let response: Response = try await put("/api/lists/\(encoded)", body: Body(title: title, description: description, isPublic: isPublic))
        guard let list = response.list else { throw APIError.noData }
        return list
    }

    func updateListSchema(listId: String, schemaDSL: String) async throws -> [ListPropertyDef] {
        struct Body: Encodable { let schema: String }
        // Response shape isn't documented; tolerate missing `properties` (e.g. {"ok":true}).
        struct Response: Decodable { let properties: [ListPropertyDef]? }
        let encoded = listId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? listId
        let response: Response = try await putCamel("/api/lists/\(encoded)/schema",
                                                    body: Body(schema: schemaDSL))
        return response.properties ?? []
    }

    func createListFolder(name: String, parentId: String?) async throws -> ListFolder {
        struct Body: Encodable { let name: String; let parentId: String? }
        struct Response: Decodable { let folder: ListFolder? }
        let response: Response = try await post("/api/folders", body: Body(name: name, parentId: parentId))
        guard let folder = response.folder else { throw APIError.noData }
        return folder
    }

    func updateListFolder(id: String, name: String?, parentId: String?) async throws -> ListFolder {
        struct Body: Encodable { let name: String?; let parentId: String? }
        struct Response: Decodable { let folder: ListFolder? }
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let response: Response = try await put("/api/folders/\(encoded)", body: Body(name: name, parentId: parentId))
        guard let folder = response.folder else { throw APIError.noData }
        return folder
    }

    func deleteListFolder(id: String) async throws {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        guard let url = URL(string: baseURL + "/api/folders/\(encoded)") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        try checkResponse(data: data, response: response)
    }

    func searchLists(q: String, limit: Int = 20, offset: Int = 0) async throws -> ([UserList], Pagination?) {
        let qEncoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        struct Response: Decodable { let lists: [UserList]; let pagination: Pagination? }
        let response: Response = try await get("/api/lists/search?q=\(qEncoded)&limit=\(limit)&offset=\(offset)")
        return (response.lists, response.pagination)
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
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"upload.\(ext)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        let (responseData, response) = try await session.data(for: request)
        try checkResponse(data: responseData, response: response)
        struct UploadResponse: Decodable { let url: String }
        return try decoder.decode(UploadResponse.self, from: responseData).url
    }

    // MARK: - Document image upload

    func uploadDocumentImage(documentId: String, data: Data, mimeType: String) async throws -> String {
        let encoded = documentId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? documentId
        guard let url = URL(string: baseURL + "/api/documents/\(encoded)/images/upload") else { throw APIError.invalidURL }
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let ext = mimeType == "image/png" ? "png" : "jpg"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"upload.\(ext)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        let (responseData, response) = try await session.data(for: request)
        try checkResponse(data: responseData, response: response)
        struct UploadResponse: Decodable { let url: String }
        return try decoder.decode(UploadResponse.self, from: responseData).url
    }

    // MARK: - Video upload

    func uploadVideo(data: Data, mimeType: String) async throws -> String {
        guard let url = URL(string: baseURL + "/api/messages/videos/upload") else { throw APIError.invalidURL }
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let ext = mimeType.contains("mp4") ? "mp4" : "mov"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"upload.\(ext)\"\r\n".data(using: .utf8)!)
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

    /// Update user preferences (theme, default visibility, advanced-post toggle).
    /// Returns the refreshed user.
    func updateUserSettings(theme: String? = nil, defaultVisibility: Bool? = nil, showAdvancedPostSettings: Bool? = nil) async throws -> User {
        struct Body: Encodable {
            let theme: String?
            let defaultVisibility: Bool?
            let showAdvancedPostSettings: Bool?
        }
        struct WrappedResponse: Decodable { let user: User? }
        let body = Body(theme: theme, defaultVisibility: defaultVisibility, showAdvancedPostSettings: showAdvancedPostSettings)
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

    // MARK: - Exports

    func exportCSV(_ type: ExportType) async throws -> Data {
        return try await getRawData("/api/exports/\(type.rawValue)")
    }

    // MARK: - List Connections

    func listConnections() async throws -> [ListConnection] {
        let response: ConnectionsResponse = try await get("/api/lists/connections")
        return response.connections
    }

    func createListConnection(sourceListId: String, targetListId: String) async throws -> ListConnection {
        struct Body: Encodable { let sourceListId: String; let targetListId: String }
        struct R: Decodable { let connection: ListConnection? }
        let r: R = try await postCamel("/api/lists/connections",
                                       body: Body(sourceListId: sourceListId, targetListId: targetListId))
        guard let conn = r.connection else { throw APIError.noData }
        return conn
    }

    func deleteListConnection(id: String) async throws {
        let enc = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        guard let url = URL(string: baseURL + "/api/lists/connections/\(enc)") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        try checkResponse(data: data, response: response)
    }

    // MARK: - List schema (structured)

    /// Persist a structured schema update. Properties with an `id` are updated in
    /// place (row data preserved); those without are created; any existing property
    /// omitted from `properties` is soft-deleted. `force` allows dropping a column
    /// that still has row data (otherwise the server returns 409).
    @discardableResult
    func updateListSchemaStructured(listId: String, properties: [SchemaPropertyInput], force: Bool = false) async throws -> [ListPropertyDef] {
        let encoded = listId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? listId
        var path = "/api/lists/\(encoded)/schema"
        if force { path += "?force=true" }
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try camelCaseEncoder.encode(StructuredSchemaBody(properties: properties))
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 409 {
            let msg = (try? decoder.decode(ErrorResponse.self, from: data))?.error
                ?? "This property still contains data."
            throw APIError.conflict(msg)
        }
        try checkResponse(data: data, response: response)
        return (try? decoder.decode(SchemaUpdateResponse.self, from: data))?.properties ?? []
    }

    // MARK: - Follow surface (Phase 5)

    func followers(userId: String, limit: Int = 30, offset: Int = 0) async throws -> (users: [FollowUser], pagination: Pagination?) {
        let encoded = userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userId
        let response: FollowersResponse = try await get("/api/follow/\(encoded)/followers?limit=\(limit)&offset=\(offset)")
        return (response.followers, response.pagination)
    }

    func following(userId: String, limit: Int = 30, offset: Int = 0) async throws -> (users: [FollowUser], pagination: Pagination?) {
        let encoded = userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userId
        let response: FollowingResponse = try await get("/api/follow/\(encoded)/following?limit=\(limit)&offset=\(offset)")
        return (response.following, response.pagination)
    }

    func mutualCounts(userId: String) async throws -> MutualCounts {
        let encoded = userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userId
        return try await get("/api/follow/\(encoded)/mutual")
    }

    func removeFollower(userId: String) async throws {
        let encoded = userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userId
        guard let url = URL(string: baseURL + "/api/follow/\(encoded)/remove") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        try checkResponse(data: data, response: response)
    }

    // MARK: - List watchers (Phase 6)

    func listWatchers(listId: String) async throws -> [ListWatcher] {
        let encoded = listId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? listId
        let response: WatchersResponse = try await get("/api/lists/\(encoded)/watchers")
        return response.watchers
    }

    func isWatchingList(listId: String) async throws -> WatchingResponse {
        let encoded = listId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? listId
        return try await get("/api/lists/\(encoded)/watchers/me")
    }

    func watchSelf(listId: String) async throws {
        struct Empty: Encodable {}
        struct Response: Decodable { let watching: Bool? }
        let encoded = listId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? listId
        let _: Response = try await postCamel("/api/lists/\(encoded)/watchers", body: Empty())
    }

    func searchWatcherCandidates(listId: String, limit: Int = 20, offset: Int = 0) async throws -> [WatcherCandidate] {
        let encoded = listId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? listId
        let response: WatcherCandidatesResponse = try await get("/api/lists/\(encoded)/watchers/users?limit=\(limit)&offset=\(offset)")
        return response.users
    }

    @discardableResult
    func addWatcher(listId: String, userId: String, role: WatcherRole) async throws -> Bool {
        struct Body: Encodable { let userId: String; let role: String }
        struct Response: Decodable { let watching: Bool? }
        let encoded = listId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? listId
        let response: Response = try await postCamel("/api/lists/\(encoded)/watchers", body: Body(userId: userId, role: role.rawValue))
        return response.watching ?? true
    }

    @discardableResult
    func setWatcherRole(listId: String, userId: String, role: WatcherRole) async throws -> String {
        struct Body: Encodable { let role: String }
        struct Response: Decodable { let role: String? }
        let encodedList = listId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? listId
        let encodedUser = userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userId
        let response: Response = try await putCamel("/api/lists/\(encodedList)/watchers/\(encodedUser)", body: Body(role: role.rawValue))
        return response.role ?? role.rawValue
    }

    func removeWatcher(listId: String, userId: String) async throws {
        let encodedList = listId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? listId
        let encodedUser = userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userId
        guard let url = URL(string: baseURL + "/api/lists/\(encodedList)/watchers/\(encodedUser)") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        try checkResponse(data: data, response: response)
    }

    // MARK: - Public browse (Phase 7)

    func publicListDetail(username: String, listId: String) async throws -> PublicListDetail {
        let u = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let l = listId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? listId
        return try await get("/api/users/\(u)/lists/\(l)")
    }

    func publicListData(username: String, listId: String, limit: Int = 50, offset: Int = 0) async throws -> PublicListData {
        let u = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let l = listId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? listId
        return try await get("/api/users/\(u)/lists/\(l)/data?limit=\(limit)&offset=\(offset)")
    }

    func publicDocuments(username: String) async throws -> PublicDocumentsResponse {
        let u = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        return try await get("/api/users/\(u)/documents")
    }

    func publicDocument(id: String) async throws -> Document {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        struct Response: Decodable { let document: Document? }
        // The endpoint may wrap the document or return it bare; tolerate both.
        let data = try await getRawData("/api/documents/\(encoded)")
        if let wrapped = try? decoder.decode(Response.self, from: data), let doc = wrapped.document {
            return doc
        }
        return try decoder.decode(Document.self, from: data)
    }

    // MARK: - Organizations (Phase 8)

    func organizations(limit: Int = 30, offset: Int = 0) async throws -> (orgs: [Organization], pagination: Pagination?) {
        let response: OrganizationsResponse = try await get("/api/organizations?limit=\(limit)&offset=\(offset)")
        return (response.organizations, response.pagination)
    }

    func organization(id: String) async throws -> Organization {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let response: OrganizationResponse = try await get("/api/organizations/\(encoded)")
        return response.organization
    }

    @discardableResult
    func createOrganization(name: String, description: String?, isPublic: Bool) async throws -> Organization? {
        struct Body: Encodable { let name: String; let description: String?; let isPublic: Bool }
        struct Response: Decodable { let organization: Organization? }
        let response: Response = try await postCamel("/api/organizations", body: Body(name: name, description: description, isPublic: isPublic))
        return response.organization
    }

    func updateOrganization(id: String, name: String?, description: String?, isPublic: Bool?) async throws {
        struct Body: Encodable { let name: String?; let description: String?; let isPublic: Bool? }
        struct Response: Decodable { let ok: Bool? }
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let _: Response = try await putCamel("/api/organizations/\(encoded)", body: Body(name: name, description: description, isPublic: isPublic))
    }

    func deleteOrganization(id: String) async throws {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        guard let url = URL(string: baseURL + "/api/organizations/\(encoded)") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        try checkResponse(data: data, response: response)
    }

    func organizationMembers(id: String, limit: Int = 50, offset: Int = 0) async throws -> (members: [OrganizationMember], pagination: Pagination?) {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let response: OrganizationMembersResponse = try await get("/api/organizations/\(encoded)/members?limit=\(limit)&offset=\(offset)")
        return (response.members, response.pagination)
    }

    func addOrganizationMember(id: String, userId: String, role: OrgRole) async throws {
        struct Body: Encodable { let userId: String; let role: String }
        struct Response: Decodable { let ok: Bool? }
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let _: Response = try await postCamel("/api/organizations/\(encoded)/members", body: Body(userId: userId, role: role.rawValue))
    }

    func setOrganizationMemberRole(id: String, userId: String, role: OrgRole, active: Bool? = nil) async throws {
        struct Body: Encodable { let role: String; let active: Bool? }
        struct Response: Decodable { let ok: Bool? }
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let encodedUser = userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userId
        let _: Response = try await putCamel("/api/organizations/\(encoded)/members/\(encodedUser)", body: Body(role: role.rawValue, active: active))
    }

    func removeOrganizationMember(id: String, userId: String) async throws {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let encodedUser = userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userId
        guard let url = URL(string: baseURL + "/api/organizations/\(encoded)/members/\(encodedUser)") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        try checkResponse(data: data, response: response)
    }

    func joinOrganization(organizationId: String) async throws {
        struct Body: Encodable { let organizationId: String }
        struct Response: Decodable { let ok: Bool? }
        let _: Response = try await postCamel("/api/user/organizations", body: Body(organizationId: organizationId))
    }

    // MARK: - Notification preferences (Phase 12 / B3)

    func notificationPreferences() async throws -> [NotificationPreference] {
        let response: NotificationPreferencesResponse = try await get("/api/user/notification-preferences")
        return response.events
    }

    @discardableResult
    func updateNotificationPreference(key: String, channels: NotificationChannels) async throws -> NotificationPreference {
        return try await patchCamel("/api/user/notification-preferences", body: NotificationPreferenceUpdate(key: key, channels: channels))
    }

    // MARK: - Message search (Phase 13 / B2)

    func searchMessages(q: String, limit: Int = 20, offset: Int = 0) async throws -> (messages: [Message], pagination: Pagination?) {
        let qEncoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        let response: MessagesResponse = try await get("/api/messages/search?q=\(qEncoded)&limit=\(limit)&offset=\(offset)")
        return (response.messages, response.pagination)
    }

    // MARK: - Moderation — report, block, mute

    func reportMessage(id: String, reason: ReportReason, detail: String?) async throws {
        struct Body: Encodable { let reason: String; let detail: String? }
        struct Response: Decodable { let reported: Bool? }
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let _: Response = try await postCamel("/api/messages/\(encoded)/report", body: Body(reason: reason.rawValue, detail: detail))
    }

    func reportUser(id: String, reason: ReportReason, detail: String?) async throws {
        struct Body: Encodable { let reason: String; let detail: String? }
        struct Response: Decodable { let reported: Bool? }
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let _: Response = try await postCamel("/api/users/\(encoded)/report", body: Body(reason: reason.rawValue, detail: detail))
    }

    func blockUser(id: String) async throws {
        struct Empty: Encodable {}
        struct Response: Decodable { let blocked: Bool? }
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let _: Response = try await postCamel("/api/users/\(encoded)/block", body: Empty())
    }

    func unblockUser(id: String) async throws {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        guard let url = URL(string: baseURL + "/api/users/\(encoded)/block") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        try checkResponse(data: data, response: response)
    }

    func blockedUsers(limit: Int = 50, offset: Int = 0) async throws -> BlockedUsersResponse {
        return try await get("/api/user/blocks?limit=\(limit)&offset=\(offset)")
    }

    func muteUser(id: String) async throws {
        struct Empty: Encodable {}
        struct Response: Decodable { let muted: Bool? }
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let _: Response = try await postCamel("/api/users/\(encoded)/mute", body: Empty())
    }

    func unmuteUser(id: String) async throws {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        guard let url = URL(string: baseURL + "/api/users/\(encoded)/mute") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        try checkResponse(data: data, response: response)
    }

    func mutedUsers(limit: Int = 50, offset: Int = 0) async throws -> MutedUsersResponse {
        return try await get("/api/user/mutes?limit=\(limit)&offset=\(offset)")
    }

    // MARK: - Push notifications (Phase 9)

    func registerPushDevice(token: String) async throws {
        struct Body: Encodable { let token: String; let platform: String }
        struct Response: Decodable { let registered: Bool? }
        let _: Response = try await postCamel("/api/push/register", body: Body(token: token, platform: "ios"))
    }

    func unregisterPushDevice(token: String) async throws {
        struct Body: Encodable { let token: String }
        guard let url = URL(string: baseURL + "/api/push/unregister") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try camelCaseEncoder.encode(Body(token: token))
        let (data, response) = try await session.data(for: request)
        try checkResponse(data: data, response: response)
    }

    // MARK: - Private helpers

    private func getRawData(_ path: String) async throws -> Data {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        try checkResponse(data: data, response: response)
        return data
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? ""
        apiLog.debug("\(method) \(path) auth=\(request.value(forHTTPHeaderField: "Authorization") != nil)")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        if status >= 400 {
            let body = String(data: data, encoding: .utf8) ?? ""
            apiLog.error("\(method) \(path) → \(status): \(body)")
        } else {
            apiLog.debug("\(method) \(path) → \(status) (\(data.count) bytes)")
        }
        try checkResponse(data: data, response: response)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            apiLog.error("Decode failed for \(path): \(error)")
            throw error
        }
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = bearerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return try await perform(request)
    }

    private func put<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
    }

    private func patch<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
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
        return try await perform(request)
    }

    private func postCamel<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try camelCaseEncoder.encode(body)
        return try await perform(request)
    }

    private func putCamel<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try camelCaseEncoder.encode(body)
        return try await perform(request)
    }

    private func patchCamel<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try camelCaseEncoder.encode(body)
        return try await perform(request)
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
