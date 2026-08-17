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
    /// 429 — rate limited. Distinct from `.status(429)` so callers (e.g. the
    /// document sync push) can back off and **retry** rather than surface a hard
    /// failure. `retryAfter` is the `Retry-After` header in seconds when present.
    case rateLimited(retryAfter: TimeInterval?)
}

enum ExportType: String, CaseIterable {
    case messages, lists, follows
    case listDataRows = "list-data-rows"
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

    // MARK: - LinkedIn posting targets

    /// Available LinkedIn destinations (personal profile, org pages, personal company
    /// pages) each flagged `enabled` per the user's saved preferences.
    func linkedInPostingTargets() async throws -> [LinkedInPostingTarget] {
        let response: LinkedInPostingTargetsResponse = try await get("/api/linkedin/posting-targets")
        return response.targets ?? []
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

    /// Fetches a single message by id (for content deep links). The endpoint may
    /// wrap the message under `message`/`data` or return it bare; tolerate all three.
    func message(id: String) async throws -> Message {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        struct WrappedMessage: Decodable { let message: Message? }
        struct WrappedData: Decodable { let data: Message? }
        let data = try await getRawData("/api/messages/\(encoded)")
        if let wrapped = try? decoder.decode(WrappedMessage.self, from: data), let msg = wrapped.message {
            return msg
        }
        if let wrapped = try? decoder.decode(WrappedData.self, from: data), let msg = wrapped.data {
            return msg
        }
        if let msg = try? decoder.decode(Message.self, from: data) {
            return msg
        }
        throw APIError.noData
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
        let response: Response = try await patchCamel("/api/messages/\(encoded)", body: Body(content: content, publiclyVisible: publiclyVisible))
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

    func lists() async throws -> [UserList] {
        let listsResponse: ListsResponse = try await get("/api/lists")
        return listsResponse.lists
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

    /// The structured GitHub source for a github-backed list create
    /// (`githubSource: { owner, repo }`, camelCase). The backend also accepts an
    /// optional `path`/`ref`, omitted here.
    struct GitHubSource: Encodable {
        let owner: String
        let repo: String
    }

    /// Creates a list. `schema` is the DSL object the create endpoint requires
    /// for local lists (see `ListSchemaDSL`); pass nil to omit it. A local list
    /// needs at least one column to be usable, so the create UI always supplies one.
    /// For a GitHub-backed list pass `githubSource`; the backend ignores `schema`
    /// in that case (issues drive the columns), so the caller should pass `schema: nil`.
    /// The endpoint returns the created list under `data`, not `list`.
    func createList(title: String, description: String?, isPublic: Bool, schema: ListSchemaDSL? = nil, githubSource: GitHubSource? = nil) async throws -> UserList {
        struct Body: Encodable {
            let title: String
            let description: String?
            let isPublic: Bool
            let schema: ListSchemaDSL?
            let githubSource: GitHubSource?

            enum CodingKeys: String, CodingKey {
                case title, description, isPublic, schema, githubSource
            }

            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(title, forKey: .title)
                try c.encode(description, forKey: .description)
                try c.encode(isPublic, forKey: .isPublic)
                try c.encodeIfPresent(schema, forKey: .schema)
                try c.encodeIfPresent(githubSource, forKey: .githubSource)
            }
        }
        struct Response: Decodable { let data: UserList? }
        let body = Body(title: title, description: description, isPublic: isPublic,
                        schema: githubSource == nil ? schema : nil, githubSource: githubSource)
        let response: Response = try await postCamel("/api/lists", body: body)
        guard let list = response.data else { throw APIError.noData }
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

    /// Offline sync pull. With `lastSyncAt` it returns a **delta** since that
    /// cursor; without it, the **full** folder/document state. Rows may carry a
    /// non-nil `deletedAt` tombstone. The response `lastSyncAt` is the next cursor.
    func documentSync(lastSyncAt: String? = nil) async throws -> DocumentSyncResponse {
        var path = "/api/documents/sync"
        if let cursor = lastSyncAt, !cursor.isEmpty {
            var components = URLComponents()
            components.queryItems = [URLQueryItem(name: "lastSyncAt", value: cursor)]
            if let query = components.percentEncodedQuery {
                path += "?" + query
            }
        }
        return try await get(path)
    }

    /// Offline sync push. Sends the queued `operations` (camelCase body
    /// `{ "operations": [...] }`) and returns the response `lastSyncAt` cursor.
    /// Per-op errors are swallowed server-side (the response only echoes the
    /// cursor), so callers must PULL afterwards to reconcile. Maps 429 to
    /// `APIError.rateLimited` so the caller can back off and keep the outbox.
    func pushDocumentSync(operations: [SyncOperation]) async throws -> String {
        struct Body: Encodable { let operations: [SyncOperation] }
        struct Response: Decodable { let lastSyncAt: String? }
        guard let url = URL(string: baseURL + "/api/documents/sync") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try camelCaseEncoder.encode(Body(operations: operations))
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 429 {
            let retryAfter = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init)
            throw APIError.rateLimited(retryAfter: retryAfter)
        }
        try checkResponse(data: data, response: response)
        let decoded = try decoder.decode(Response.self, from: data)
        guard let cursor = decoded.lastSyncAt else { throw APIError.noData }
        return cursor
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

    // MARK: - Document templates (G3)

    /// Starter templates a subscriber can copy from. Free for any authenticated
    /// user to read; only creating from one is subscriber-gated.
    func documentTemplates() async throws -> [DocumentTemplate] {
        let response: DocumentTemplatesResponse = try await get("/api/documents/templates")
        return response.templates
    }

    /// Copies a template into a new document (subscriber-only). Body is camelCase
    /// (`templateDocumentId`, `targetFolderId`) — pass nil to create at root. The
    /// endpoint may wrap the document or return it bare; tolerate both like createDocument.
    func createDocumentFromTemplate(templateDocumentId: String, targetFolderId: String?) async throws -> Document {
        struct Body: Encodable { let templateDocumentId: String; let targetFolderId: String? }
        struct Response: Decodable { let document: Document? }
        let body = Body(templateDocumentId: templateDocumentId, targetFolderId: targetFolderId)
        let data = try await postCamelRawData("/api/documents/from-template", body: body)
        if let wrapped = try? decoder.decode(Response.self, from: data), let doc = wrapped.document {
            return doc
        }
        if let doc = try? decoder.decode(Document.self, from: data) {
            return doc
        }
        throw APIError.noData
    }

    /// The backend reads camelCase (`isPublic`) directly from the body, so this uses
    /// the camelCase encoder. Nil fields are omitted (left unchanged).
    func updateList(id: String, title: String?, description: String?, isPublic: Bool?) async throws -> UserList {
        struct Body: Encodable {
            let title: String?
            let description: String?
            let isPublic: Bool?

            enum CodingKeys: String, CodingKey {
                case title, description, isPublic
            }

            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encodeIfPresent(title, forKey: .title)
                try c.encodeIfPresent(description, forKey: .description)
                try c.encodeIfPresent(isPublic, forKey: .isPublic)
            }
        }
        struct Response: Decodable { let list: UserList? }
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let response: Response = try await putCamel("/api/lists/\(encoded)", body: Body(title: title, description: description, isPublic: isPublic))
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

    func searchLists(q: String, limit: Int = 20, offset: Int = 0) async throws -> ([UserList], Pagination?) {
        let qEncoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        struct Response: Decodable { let lists: [UserList]; let pagination: Pagination? }
        let response: Response = try await get("/api/lists/search?q=\(qEncoded)&limit=\(limit)&offset=\(offset)")
        return (response.lists, response.pagination)
    }

    // MARK: - GitHub-backed lists (G4)

    /// Repositories the linked GitHub account can access (`GET /api/github/repos`,
    /// Bearer). The endpoint forwards the raw GitHub REST array (not wrapped).
    /// Returns 400 "GitHub account not linked" when no GitHub identity is linked.
    func githubRepos() async throws -> [GitHubRepo] {
        return try await get("/api/github/repos")
    }

    /// Open (or `state`) issues for a repo (`GET /api/github/issues?repo=owner/repo`,
    /// Bearer). Raw GitHub REST array; decode defensively.
    func githubIssues(repo: String, state: String = "open") async throws -> [GitHubIssue] {
        var components = URLComponents(string: baseURL + "/api/github/issues")
        components?.queryItems = [
            URLQueryItem(name: "repo", value: repo),
            URLQueryItem(name: "state", value: state),
        ]
        let query = components?.percentEncodedQuery.map { "?" + $0 } ?? ""
        return try await get("/api/github/issues" + query)
    }

    /// Re-syncs a GitHub-backed list's cached rows from GitHub issues
    /// (`POST /api/lists/:id/refresh`, Bearer). 400 if the list isn't github-backed
    /// or its repo is missing.
    func refreshList(id: String) async throws {
        struct Empty: Encodable {}
        struct Response: Decodable { let message: String?; let count: Int? }
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let _: Response = try await postCamel("/api/lists/\(encoded)/refresh", body: Empty())
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

    /// Prefix search over usernames/display names (G6). The backend rejects a
    /// blank `q` with 400 `missing_query`, so callers must not pass an empty query.
    /// Reuses `FollowUser` — the response rows share its id/username/displayName/avatar shape.
    func searchUsers(query: String, limit: Int = 20) async throws -> [FollowUser] {
        struct Response: Decodable { let users: [FollowUser] }
        var components = URLComponents(string: baseURL + "/api/users/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        // percentEncodedQuery escapes reserved characters (e.g. `&` in the query
        // string) so a query like "a&b" doesn't split into spurious parameters.
        let encodedQuery = components?.percentEncodedQuery.map { "?" + $0 } ?? ""
        let response: Response = try await get("/api/users/search" + encodedQuery)
        return response.users
    }

    // MARK: - Tag discovery (G13)

    /// Most-used tags across public messages within a trailing window.
    /// `window` is one of `day`/`week`/`month` (backend defaults unknown values to
    /// `week`); `limit` is clamped server-side to ≤100.
    func trendingTags(window: String = "week", limit: Int = 20) async throws -> [TrendingTag] {
        struct Response: Decodable { let tags: [TrendingTag] }
        var components = URLComponents(string: baseURL + "/api/tags/trending")
        components?.queryItems = [
            URLQueryItem(name: "window", value: window),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        let encodedQuery = components?.percentEncodedQuery.map { "?" + $0 } ?? ""
        let response: Response = try await get("/api/tags/trending" + encodedQuery)
        return response.tags
    }

    /// Tags on public messages matching a case-insensitive literal prefix. A leading
    /// `#` is stripped server-side; a blank prefix is rejected with 400, so callers
    /// should guard against empty input. `limit` is clamped server-side to ≤50.
    func tagAutocomplete(query: String, limit: Int = 10) async throws -> [TagSuggestion] {
        struct Response: Decodable { let tags: [TagSuggestion] }
        var components = URLComponents(string: baseURL + "/api/tags/autocomplete")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        let encodedQuery = components?.percentEncodedQuery.map { "?" + $0 } ?? ""
        let response: Response = try await get("/api/tags/autocomplete" + encodedQuery)
        return response.tags
    }

    // MARK: - Link preview (G14)

    /// Fetches Open Graph / link metadata for a single URL so the composer can show a
    /// live preview before a post is created. The endpoint always returns a terminal
    /// item (`fetchStatus` `success`|`failed`, never pending) and is rate-limited
    /// (429). Callers should treat a 429 or a `failed` status as "no preview" rather
    /// than a hard error.
    func linkMetadata(url: String) async throws -> LinkMetadataItem {
        struct Response: Decodable { let link: LinkMetadataItem }
        var components = URLComponents(string: baseURL + "/api/link-metadata")
        components?.queryItems = [URLQueryItem(name: "url", value: url)]
        let encodedQuery = components?.percentEncodedQuery.map { "?" + $0 } ?? ""
        let response: Response = try await get("/api/link-metadata" + encodedQuery)
        return response.link
    }

    // MARK: - Share-link resolvers (G10)

    /// Resolves a document share-link token to a read-only view. Auth is optional on
    /// this endpoint (anonymous read works); a Bearer token, if present, is ignored
    /// for the read. Throws `.server`/`.status(404)` for an unknown/expired/revoked
    /// token and `.status(429)` when rate-limited.
    func resolveSharedDocument(token: String) async throws -> SharedDocumentResolution {
        let t = token.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? token
        return try await get("/api/documents/shared/\(t)")
    }

    // MARK: - Notifications

    func notifications() async throws -> NotificationsResponse {
        return try await get("/api/notifications?scope=tray")
    }

    func markNotificationRead(id: String) async throws {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        struct Empty: Encodable {}
        struct OkResponse: Decodable { let ok: Bool }
        let _: OkResponse = try await patch("/api/notifications/\(encoded)/read", body: Empty())
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
        let wrapped: WrappedResponse = try await patchCamel("/api/user/update", body: body)
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
        let wrapped: WrappedResponse = try await patchCamel("/api/user/update", body: body)
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

    /// Creates a directed connection `fromList → toList`. By convention the
    /// `fromList` is the parent of the `toList`. The backend responds with the
    /// raw connection object (not wrapped).
    func createListConnection(fromListId: String, toListId: String) async throws -> ListConnection {
        struct Body: Encodable { let fromListId: String; let toListId: String }
        let conn: ListConnection = try await postCamel("/api/lists/connections",
                                                       body: Body(fromListId: fromListId, toListId: toListId))
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

    func searchWatcherCandidates(listId: String, limit: Int = 20, offset: Int = 0, search: String? = nil) async throws -> [WatcherCandidate] {
        let encoded = listId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? listId
        var path = "/api/lists/\(encoded)/watchers/users?limit=\(limit)&offset=\(offset)"
        if let search, !search.isEmpty {
            let q = search.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? search
            path += "&search=\(q)"
        }
        let response: WatcherCandidatesResponse = try await get(path)
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

    // MARK: - Sharing (G2): share-links & document collaborators

    func shareLinks(kind: ShareResourceKind, id: String) async throws -> [ShareLink] {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let response: ShareLinksResponse = try await get("/api/\(kind.pathSegment)/\(encoded)/share-links")
        return response.shareLinks
    }

    func createShareLink(kind: ShareResourceKind, id: String, role: WatcherRole = .watcher, expiresAt: String? = nil) async throws -> ShareLink {
        struct Body: Encodable { let role: String; let expiresAt: String? }
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return try await postCamel("/api/\(kind.pathSegment)/\(encoded)/share-links", body: Body(role: role.rawValue, expiresAt: expiresAt))
    }

    func revokeShareLink(kind: ShareResourceKind, id: String, token: String) async throws {
        let encodedId = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? token
        guard let url = URL(string: baseURL + "/api/\(kind.pathSegment)/\(encodedId)/share-links/\(encodedToken)") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        try checkResponse(data: data, response: response)
    }

    // MARK: - Sharing: email share-invites (owner-only send/list/revoke)

    /// Owner-side invites for a list or document. The recipient claims the invite
    /// on the web (session-only), so iOS only ever sends, lists, and revokes.
    func shareInvites(kind: ShareResourceKind, id: String) async throws -> [ShareInvite] {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let response: ShareInvitesResponse = try await get("/api/\(kind.pathSegment)/\(encoded)/invites")
        return response.invites
    }

    /// Sends an email invite (subscriber-gated, rate-limited server-side). Body is
    /// camelCase (`email`, `role`, `expiresAt`); `expiresAt` is omitted when nil.
    func createShareInvite(kind: ShareResourceKind, id: String, email: String, role: WatcherRole = .watcher, expiresAt: String? = nil) async throws -> CreateShareInviteResponse {
        struct Body: Encodable { let email: String; let role: String; let expiresAt: String? }
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return try await postCamel("/api/\(kind.pathSegment)/\(encoded)/invites", body: Body(email: email, role: role.rawValue, expiresAt: expiresAt))
    }

    func revokeShareInvite(kind: ShareResourceKind, id: String, token: String) async throws {
        let encodedId = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? token
        guard let url = URL(string: baseURL + "/api/\(kind.pathSegment)/\(encodedId)/invites/\(encodedToken)") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        try checkResponse(data: data, response: response)
    }

    func documentCollaborators(id: String) async throws -> [DocumentCollaborator] {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let response: DocumentCollaboratorsResponse = try await get("/api/documents/\(encoded)/collaborators")
        return response.collaborators
    }

    @discardableResult
    func addDocumentCollaborator(id: String, userId: String, role: WatcherRole = .watcher, notify: Bool = false) async throws -> DocumentCollaborator {
        struct Body: Encodable { let userId: String; let role: String; let notify: Bool }
        struct Response: Decodable { let collaborator: DocumentCollaborator? }
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let response: Response = try await postCamel("/api/documents/\(encoded)/collaborators", body: Body(userId: userId, role: role.rawValue, notify: notify))
        guard let collaborator = response.collaborator else {
            return DocumentCollaborator(userId: userId, role: role.rawValue, username: nil, displayName: nil, avatar: nil)
        }
        return collaborator
    }

    @discardableResult
    func setDocumentCollaboratorRole(id: String, userId: String, role: WatcherRole, notify: Bool = false) async throws -> String {
        struct Body: Encodable { let role: String; let notify: Bool }
        struct Response: Decodable { let role: String? }
        let encodedId = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let encodedUser = userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userId
        let response: Response = try await putCamel("/api/documents/\(encodedId)/collaborators/\(encodedUser)", body: Body(role: role.rawValue, notify: notify))
        return response.role ?? role.rawValue
    }

    func removeDocumentCollaborator(id: String, userId: String) async throws {
        let encodedId = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let encodedUser = userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userId
        guard let url = URL(string: baseURL + "/api/documents/\(encodedId)/collaborators/\(encodedUser)") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        try checkResponse(data: data, response: response)
    }

    func searchDocumentCollaboratorCandidates(id: String, query: String) async throws -> [WatcherCandidate] {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let response: WatcherCandidatesResponse = try await get("/api/documents/\(encoded)/collaborators/users?q=\(q)")
        return response.users
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

    // MARK: - Active sessions (G12)

    func userSessions() async throws -> [UserSession] {
        let response: UserSessionsResponse = try await get("/api/user/sessions")
        return response.sessions
    }

    func revokeSession(id: String) async throws {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        guard let url = URL(string: baseURL + "/api/user/sessions/\(encoded)") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        try checkResponse(data: data, response: response)
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

    // MARK: - Direct messages

    /// Lists messages in a DM folder. `nextCursor` paginates further into that folder.
    func directMessages(folder: DMFolder, cursor: String? = nil) async throws -> DMListResponse {
        var components = URLComponents(string: baseURL + "/api/dm")
        components?.queryItems = [URLQueryItem(name: "folder", value: folder.rawValue)]
        if let cursor { components?.queryItems?.append(URLQueryItem(name: "cursor", value: cursor)) }
        let query = components?.percentEncodedQuery.map { "?" + $0 } ?? ""
        return try await get("/api/dm" + query)
    }

    /// Sends a direct message. Body is 1–10000 chars; camelCase keys (`recipientId`,
    /// `imageUrls`) — snake_case would be dropped server-side.
    @discardableResult
    func sendDirectMessage(recipientId: String, body: String, imageUrls: [String] = []) async throws -> DMMessage {
        struct Body: Encodable { let recipientId: String; let body: String; let imageUrls: [String] }
        let response: DMMessageResponse = try await postCamel("/api/dm", body: Body(recipientId: recipientId, body: body, imageUrls: imageUrls))
        return response.message
    }

    func directMessage(id: String) async throws -> DMMessage {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let response: DMMessageResponse = try await get("/api/dm/\(encoded)")
        return response.message
    }

    @discardableResult
    func markDMRead(id: String) async throws -> Int {
        struct Empty: Encodable {}
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let response: DMUpdatedResponse = try await post("/api/dm/\(encoded)/read", body: Empty())
        return response.updated
    }

    func trashDM(id: String) async throws {
        struct Empty: Encodable {}
        struct Response: Decodable { let ok: Bool? }
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let _: Response = try await post("/api/dm/\(encoded)/trash", body: Empty())
    }

    func restoreDM(id: String) async throws {
        struct Empty: Encodable {}
        struct Response: Decodable { let ok: Bool? }
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let _: Response = try await post("/api/dm/\(encoded)/restore", body: Empty())
    }

    /// Users you may DM (mutual-follow set).
    func dmRecipients() async throws -> [DMUser] {
        let response: DMRecipientsResponse = try await get("/api/dm/recipients")
        return response.recipients
    }

    /// The conversation with `username`. Opening a thread auto-marks received messages read.
    func dmThread(username: String) async throws -> DMThread {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        return try await get("/api/dm/thread/\(encoded)")
    }

    /// New messages in the thread since `after` (the client's last known message id).
    /// Auto-marks received messages read.
    func dmThreadUpdates(username: String, after: String) async throws -> DMThread {
        let encodedUser = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let encodedAfter = after.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? after
        return try await get("/api/dm/thread/\(encodedUser)/updates?after=\(encodedAfter)")
    }

    func dmUnreadCount() async throws -> Int {
        let response: DMUnreadCountResponse = try await get("/api/dm/unread-count")
        return response.count
    }

    /// Uploads a DM image (multipart field `file`). Requires a verified email — not a subscription.
    func uploadDMImage(data: Data, mimeType: String) async throws -> String {
        guard let url = URL(string: baseURL + "/api/dm/images/upload") else { throw APIError.invalidURL }
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

    private func postCamelRawData<B: Encodable>(_ path: String, body: B) async throws -> Data {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try camelCaseEncoder.encode(body)
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
