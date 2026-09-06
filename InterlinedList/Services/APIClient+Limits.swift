//
//  APIClient+Limits.swift
//  InterlinedList
//

import Foundation

extension APIClient {

    /// `GET /api/limits` — the upload and content caps the backend enforces.
    /// Public: it takes no auth and is safe to call before sign-in.
    func serverLimits() async throws -> ServerLimits {
        try await get("/api/limits")
    }
}
