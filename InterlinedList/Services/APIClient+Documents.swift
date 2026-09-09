import Foundation

/// How a folder update should treat `parentId`.
///
/// `PUT /api/documents/folders/{id}` only validates and applies a move when the
/// `parentId` key is *present* in the body, and Swift's synthesized `Encodable`
/// drops a `nil` optional rather than writing `null`. Without this distinction a
/// rename would be indistinguishable from a move to root.
enum DocumentFolderParentUpdate: Equatable {
    /// Leave the folder where it is — omit `parentId` entirely.
    case unchanged
    /// Move to the top level — send an explicit `null`.
    case root
    /// Move under another folder.
    case folder(String)
}

extension APIClient {
    /// Renames and/or moves a document folder (`PUT /api/documents/folders/{id}`).
    ///
    /// The route reads plain camelCase keys (`name`, `parentId`), so this goes
    /// through `putCamel` — the snake_case `put` would send `parent_id`, which the
    /// server ignores, silently dropping the move.
    ///
    /// A move that would make the folder its own ancestor is rejected server-side
    /// with a `400` whose body carries readable text, which `checkResponse` surfaces
    /// as `APIError.server(_:)`. A name that collides with a sibling comes back the
    /// same way with a `409`.
    func updateDocumentFolder(id: String,
                              name: String? = nil,
                              parentId: DocumentFolderParentUpdate = .unchanged) async throws -> DocumentFolder {
        struct Response: Decodable { let folder: DocumentFolder? }
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let response: Response = try await putCamel(
            "/api/documents/folders/\(encoded)",
            body: UpdateDocumentFolderBody(name: name, parentId: parentId))
        guard let folder = response.folder else { throw APIError.noData }
        return folder
    }
}

/// Encodes only the fields the caller actually wants changed, so a rename never
/// re-sends (and re-validates) the folder's parent.
private struct UpdateDocumentFolderBody: Encodable {
    let name: String?
    let parentId: DocumentFolderParentUpdate

    private enum CodingKeys: String, CodingKey { case name, parentId }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        switch parentId {
        case .unchanged:
            break
        case .root:
            try container.encodeNil(forKey: .parentId)
        case .folder(let id):
            try container.encode(id, forKey: .parentId)
        }
    }
}
