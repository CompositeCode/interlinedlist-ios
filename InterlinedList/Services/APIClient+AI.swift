//
//  APIClient+AI.swift
//  InterlinedList
//

import Foundation
import os.log

private let aiLog = Logger(subsystem: "com.interlinedlist.app", category: "APIClient+AI")

/// A validated preview from `/api/ai/suggest`. Nothing has been written yet.
struct AISuggestion: Equatable {
    let artifact: AIArtifact
    let usage: AIUsage?
    let quota: AIQuota?
}

/// The result of persisting a confirmed artifact via `/api/ai/generate`.
struct AIGenerationResult: Equatable {
    let created: AICreated
    let quota: AIQuota?
}

/// AI writing assistance (`/api/ai/{status,suggest,generate}`).
///
/// This is the one feature that does **not** route through the shared transport
/// seam in `APIClientTransport.swift`, for two reasons:
///
///  - It carries model-authored JSON that must survive a suggest → generate round
///    trip verbatim. The shared `decoder` converts from snake_case, which would
///    rewrite a Powered Template's DSL field keys and fail the server's
///    re-validation, so this file uses plain coders.
///  - `checkResponse` maps a failure onto `APIError`, dropping the machine `code`
///    and the `Retry-After` header. The AI error contract is built on both.
extension APIClient {

    func aiStatus() async throws -> AIStatus {
        try await aiRequest("/api/ai/status", method: "GET", body: nil)
    }

    func aiSuggest(
        feature: AIFeature,
        input: String,
        context: AIContext? = nil,
        maxOutputTokens: Int? = nil
    ) async throws -> AISuggestion {
        struct Body: Encodable {
            let feature: AIFeature
            let input: String
            let context: AIContext?
            let maxOutputTokens: Int?
        }
        struct Response: Decodable {
            let artifact: AIArtifact
            let usage: AIUsage?
            let quota: AIQuota?
        }
        let body = Body(feature: feature, input: input, context: context, maxOutputTokens: maxOutputTokens)
        let response: Response = try await aiRequest(
            "/api/ai/suggest",
            method: "POST",
            body: try aiEncode(body)
        )
        return AISuggestion(artifact: response.artifact, usage: response.usage, quota: response.quota)
    }

    func aiGenerate(
        feature: AIFeature,
        artifact: AIArtifact,
        channels: [String]? = nil,
        scheduleImmediately: Bool? = nil,
        crossPost: AIComposerCrossPost? = nil
    ) async throws -> AIGenerationResult {
        struct Body: Encodable {
            let feature: AIFeature
            let artifact: AIArtifact
            let channels: [String]?
            let scheduleImmediately: Bool?
            let crossPost: AIComposerCrossPost?
        }
        struct Response: Decodable {
            let created: AICreated
            let quota: AIQuota?
        }
        let body = Body(
            feature: feature,
            artifact: artifact,
            channels: channels,
            scheduleImmediately: scheduleImmediately,
            crossPost: crossPost
        )
        let response: Response = try await aiRequest(
            "/api/ai/generate",
            method: "POST",
            body: try aiEncode(body)
        )
        return AIGenerationResult(created: response.created, quota: response.quota)
    }

    // MARK: - Private

    /// Verbatim encoder: the AI wire format is camelCase, and a Powered
    /// Template's DSL carries snake_case field keys that must not be rewritten.
    private func aiEncode<B: Encodable>(_ body: B) throws -> Data {
        try JSONEncoder().encode(body)
    }

    private func aiRequest<Response: Decodable>(
        _ path: String,
        method: String,
        body: Data?
    ) async throws -> Response {
        guard let url = URL(string: baseURL + path) else { throw AIServiceError.transport }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token = bearerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            aiLog.error("\(method) \(path) transport failure: \(error.localizedDescription)")
            throw AIServiceError.transport
        }

        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let failure = Self.aiFailure(status: http.statusCode, data: data, headers: http)
            aiLog.error("\(method) \(path) → \(http.statusCode)")
            throw failure
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            aiLog.error("\(method) \(path) decode failed: \(error.localizedDescription)")
            throw AIServiceError.invalidOutput
        }
    }

    private static func aiFailure(status: Int, data: Data, headers: HTTPURLResponse) -> AIServiceError {
        struct ErrorBody: Decodable {
            let error: String?
            let code: String?
        }
        let parsed = try? JSONDecoder().decode(ErrorBody.self, from: data)
        let retryAfter = headers.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
        return AIServiceError(
            status: status,
            code: parsed?.code,
            message: parsed?.error,
            retryAfter: retryAfter
        )
    }
}
