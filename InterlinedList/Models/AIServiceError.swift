//
//  AIServiceError.swift
//  InterlinedList
//

import Foundation

/// Typed mapping of the `/api/ai/*` error contract (`{ error, code }` + status).
///
/// AI is a subscriber entitlement served from the app's own server-side provider
/// key — there is no user-supplied key — so `no_provider_configured` is a server
/// outage, not a user-fixable state, and no case here may steer the user toward
/// a purchase (App Store Guideline 3.1.1). Raw backend copy is never surfaced
/// for the subscription gate.
enum AIServiceError: Error, Equatable {
    /// 401 — the session token was rejected. Views route this to
    /// `AuthState.handleUnauthorized()`, which re-validates before logging out.
    case unauthorized
    /// 403 `subscription_required` — shouldn't reach a gated control; if it
    /// does, hide the affordance and refresh `/status`.
    case subscriptionRequired
    /// 409 `no_provider_configured` — the server has no provider key or the
    /// provider is down. Transient; hide the control for the session.
    case unavailable
    /// 422 `invalid_input` — the request failed the server's own size/shape
    /// checks. The message is safe to show (word limits).
    case invalidInput(String)
    /// 422 `invalid_ai_output` / `refused` — the model returned junk or declined.
    case invalidOutput
    /// 429 `quota_exceeded` — the 50/day budget is spent.
    case quotaExceeded
    /// 429 `rate_limited` — short-window burst limit; honor `Retry-After`.
    case rateLimited(retryAfter: TimeInterval?)
    /// 5xx `provider_error` — upstream failure.
    case providerError
    /// Transport failure, malformed response, or an unmapped status.
    case transport

    /// Maps an HTTP status, the `{ error, code }` body, and the `Retry-After`
    /// header onto a case. The whole wire-to-case mapping lives here.
    init(status: Int, code: String?, message: String? = nil, retryAfter: TimeInterval? = nil) {
        switch code {
        case "unauthorized": self = .unauthorized
        case "subscription_required": self = .subscriptionRequired
        case "no_provider_configured": self = .unavailable
        case "invalid_input": self = .invalidInput(message ?? "That request wasn't accepted.")
        case "invalid_ai_output", "refused": self = .invalidOutput
        case "quota_exceeded": self = .quotaExceeded
        case "rate_limited": self = .rateLimited(retryAfter: retryAfter)
        case "provider_error": self = .providerError
        default:
            // No code, or one this build doesn't know — fall back to the status.
            switch status {
            case 401: self = .unauthorized
            case 403: self = .subscriptionRequired
            case 409: self = .unavailable
            case 422: self = .invalidOutput
            case 429: self = .rateLimited(retryAfter: retryAfter)
            case 500...599: self = .providerError
            default: self = .transport
            }
        }
    }

    /// Neutral in-app copy. Never mentions price, subscriptions, or provider keys.
    var userMessage: String {
        switch self {
        case .unauthorized:
            return "Your session expired. Sign in again to continue."
        case .subscriptionRequired:
            return "AI isn't available on this account."
        case .unavailable:
            return "AI is unavailable right now. Try again later."
        case .invalidInput(let message):
            return message
        case .invalidOutput:
            return "The assistant returned an unusable result. Try again."
        case .quotaExceeded:
            return "You've reached today's AI limit. It resets tomorrow."
        case .rateLimited(let retryAfter):
            guard let seconds = retryAfter, seconds > 0 else {
                return "Too many AI requests. Try again in a moment."
            }
            return "Too many AI requests. Try again in \(Int(seconds.rounded()))s."
        case .providerError:
            return "The AI request failed. Try again."
        case .transport:
            return "Connection failed. Please try again."
        }
    }

    /// Whether re-running the same request is worth offering.
    var isRetryable: Bool {
        switch self {
        case .invalidOutput, .providerError, .transport, .rateLimited:
            return true
        case .unauthorized, .subscriptionRequired, .unavailable, .invalidInput, .quotaExceeded:
            return false
        }
    }

    /// Whether the affordance should disappear for the rest of the session: the
    /// entitlement isn't there, or the server can't serve AI at all.
    var hidesAffordance: Bool {
        switch self {
        case .subscriptionRequired, .unavailable:
            return true
        default:
            return false
        }
    }
}
