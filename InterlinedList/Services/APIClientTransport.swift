//
//  APIClientTransport.swift
//  InterlinedList
//

import Foundation
import os.log

private let transportLog = Logger(subsystem: "com.interlinedlist.app", category: "APIClient")

/// The HTTP seam every `APIClient` endpoint is built on: URL assembly, auth
/// header, body encoding, status checking, decoding.
///
/// **Why these are `internal` and not `private`.** Swift's `private` is
/// file-scoped, so a `private` verb helper living in `APIClient.swift` is
/// invisible to an `extension APIClient` in any *other* file. That made
/// `APIClient.swift` a single 1800-line class body every new endpoint had to be
/// appended to. Keeping the transport here, at module scope, is what lets a
/// feature add its endpoints in its own `APIClient+<Feature>.swift` instead
/// (remember to register the new file in `project.pbxproj` — no synced groups).
///
/// **Picking a verb helper.** Match the *body encoding the route expects*, not
/// the verb alone — the wrong one fails silently (see CLAUDE.md):
/// - `post` / `put` / `patch` — snake_case bodies (`convertToSnakeCase`)
/// - `postCamel` / `putCamel` / `patchCamel` — camelCase bodies, which the many
///   messages / lists / orgs / watchers / identities routes require
/// Responses always decode with `convertFromSnakeCase`.
extension APIClient {

    // MARK: - Reads

    func get<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        authorize(&request)
        return try await perform(request)
    }

    /// GET returning the undecoded body — for routes that answer with something
    /// other than JSON (CSV exports).
    func getRawData(_ path: String) async throws -> Data {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        authorize(&request)
        let (data, response) = try await session.data(for: request)
        try checkResponse(data: data, response: response)
        return data
    }

    /// GET that maps selected non-2xx statuses to caller-supplied errors *before*
    /// the generic body-driven mapping runs. A route answering 403/404 with an
    /// `{"error": …}` body otherwise arrives as `.forbidden`/`.server`, which
    /// loses the distinction a permalink opener needs: "you have no access here"
    /// reads very differently from "the server had a problem".
    func get<T: Decodable>(_ path: String, mappingStatuses statusErrors: [Int: Error]) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        authorize(&request)
        let (data, response) = try await session.data(for: request)
        if let status = (response as? HTTPURLResponse)?.statusCode, let mapped = statusErrors[status] {
            throw mapped
        }
        try checkResponse(data: data, response: response)
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - Writes (snake_case bodies)

    func post<T: Decodable, B: Encodable>(_ path: String, body: B, authenticated: Bool = true) async throws -> T {
        var request = try jsonRequest(path, method: "POST", authenticated: authenticated)
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
    }

    func put<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        var request = try jsonRequest(path, method: "PUT")
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
    }

    func patch<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        var request = try jsonRequest(path, method: "PATCH")
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
    }

    // MARK: - Writes (camelCase bodies)

    func postCamel<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        var request = try jsonRequest(path, method: "POST")
        request.httpBody = try camelCaseEncoder.encode(body)
        return try await perform(request)
    }

    func putCamel<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        var request = try jsonRequest(path, method: "PUT")
        request.httpBody = try camelCaseEncoder.encode(body)
        return try await perform(request)
    }

    func patchCamel<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        var request = try jsonRequest(path, method: "PATCH")
        request.httpBody = try camelCaseEncoder.encode(body)
        return try await perform(request)
    }

    /// POST returning the undecoded body — for routes whose response is not a
    /// fixed `Decodable` shape (the document sync push).
    func postCamelRawData<B: Encodable>(_ path: String, body: B) async throws -> Data {
        var request = try jsonRequest(path, method: "POST")
        request.httpBody = try camelCaseEncoder.encode(body)
        let (data, response) = try await session.data(for: request)
        try checkResponse(data: data, response: response)
        return data
    }

    // MARK: - Deletes

    /// Bodyless DELETE with nothing to decode. Delete routes answer with `{}`,
    /// `{ok:true}`, or `204 No Content` interchangeably, so the body is dropped;
    /// a non-2xx still throws through `checkResponse`.
    func delete(_ path: String) async throws {
        _ = try await deleteRawData(path)
    }

    /// DELETE whose response body carries state the caller needs (un-dig returns
    /// the new dig count).
    func deleteDecoding<T: Decodable>(_ path: String) async throws -> T {
        let data = try await deleteRawData(path)
        return try decoder.decode(T.self, from: data)
    }

    /// DELETE with a camelCase JSON body — a few routes identify their target in
    /// the body rather than the path (identity unlink, push unregister).
    func deleteCamel<B: Encodable>(_ path: String, body: B) async throws {
        var request = try jsonRequest(path, method: "DELETE")
        request.httpBody = try camelCaseEncoder.encode(body)
        let (data, response) = try await session.data(for: request)
        try checkResponse(data: data, response: response)
    }

    private func deleteRawData(_ path: String) async throws -> Data {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        authorize(&request)
        let (data, response) = try await session.data(for: request)
        try checkResponse(data: data, response: response)
        return data
    }

    // MARK: - Uploads

    /// POSTs a single-file `multipart/form-data` body under the field name
    /// `file`, which is the shape every upload route on the backend expects.
    /// Returns the undecoded body so each caller decodes its own response shape.
    func postMultipartRawData(_ path: String, fileName: String, mimeType: String, fileData: Data) async throws -> Data {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        authorize(&request)
        request.httpBody = Self.multipartFileBody(boundary: boundary, fileName: fileName, mimeType: mimeType, fileData: fileData)
        let (data, response) = try await session.data(for: request)
        try checkResponse(data: data, response: response)
        return data
    }

    /// Percent-encodes one path segment. `?? segment` keeps the call sites free
    /// of force-unwraps; encoding only fails for inputs a path can't hold anyway.
    func pathSegment(_ segment: String) -> String {
        segment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? segment
    }

    // MARK: - Private

    private func jsonRequest(_ path: String, method: String, authenticated: Bool = true) throws -> URLRequest {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated { authorize(&request) }
        return request
    }

    private func authorize(_ request: inout URLRequest) {
        guard let bearerToken else { return }
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
    }

    /// `Data(_:utf8)` rather than `.data(using: .utf8)!` — the hand-rolled form
    /// this replaces force-unwrapped five times per upload, on a production path.
    private static func multipartFileBody(boundary: String, fileName: String, mimeType: String, fileData: Data) -> Data {
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(fileData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? ""
        transportLog.debug("\(method) \(path) auth=\(request.value(forHTTPHeaderField: "Authorization") != nil)")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        if status >= 400 {
            let body = String(data: data, encoding: .utf8) ?? ""
            transportLog.error("\(method) \(path) → \(status): \(body)")
        } else {
            transportLog.debug("\(method) \(path) → \(status) (\(data.count) bytes)")
        }
        try checkResponse(data: data, response: response)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            transportLog.error("Decode failed for \(path): \(error)")
            throw error
        }
    }

    /// The `{"error": …}` message a route sends alongside a failure, when it
    /// sends one. Endpoints that map a status themselves (409 → `.conflict`)
    /// read the message through this rather than the wire type.
    func serverErrorMessage(from data: Data) -> String? {
        (try? decoder.decode(ErrorResponse.self, from: data))?.error
    }

    /// Maps a non-2xx response onto `APIError`. Note 401 is deliberately a bare
    /// `.status(401)`: it does **not** mean "logged out" — some routes only accept
    /// session cookies and reject a valid Bearer — so views re-validate through
    /// `authState.handleUnauthorized()` rather than logging out (CLAUDE.md).
    func checkResponse(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 401 {
            throw APIError.status(401)
        }
        if http.statusCode >= 400 {
            let serverMessage = serverErrorMessage(from: data)
            if http.statusCode == 403, let serverMessage {
                throw APIError.forbidden(serverMessage)
            }
            if let serverMessage {
                throw APIError.server(serverMessage)
            }
            throw APIError.status(http.statusCode)
        }
    }
}

private struct ErrorResponse: Decodable {
    let error: String
}
