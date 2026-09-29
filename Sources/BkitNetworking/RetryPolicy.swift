import Foundation

/// When a failed request is tried again, and how long to wait first.
///
/// Retries a retryable status (429, 502, 503, 504 by default) or a transient connection error,
/// with exponential backoff and jitter — honouring the server's `Retry-After` when it sends one.
/// Only idempotent methods are retried unless `retriesNonIdempotent` is set: a POST that timed
/// out may have gone through. Cancellation stops it at once, mid-wait included.
public struct RetryPolicy: Sendable {
    /// Waits between attempts. `live` sleeps the task; tests pass one that records and returns.
    public struct Sleeper: Sendable {
        public let sleep: @Sendable (Duration) async throws -> Void

        public init(_ sleep: @escaping @Sendable (Duration) async throws -> Void) {
            self.sleep = sleep
        }

        public static let live = Sleeper { try await Task.sleep(for: $0) }
    }

    /// Attempts in all, the first included: 1 means never retry.
    public var maxAttempts: Int
    /// The wait before the first retry; each later one doubles, up to `maxDelay`.
    public var baseDelay: Duration
    public var maxDelay: Duration
    /// How much of each wait is random, 0…1: 0.2 spreads a 1 s wait over 0.8–1.2 s, so clients
    /// that failed together don't all come back together.
    public var jitter: Double
    public var retryableStatuses: Set<Int>
    /// Also retry POST and PATCH. Only for requests the server de-duplicates (an idempotency key).
    public var retriesNonIdempotent: Bool
    /// A `Retry-After` longer than this isn't waited for: the error is thrown instead.
    public var maxRetryAfter: Duration
    public var sleeper: Sleeper
    /// 0..<1, for the jitter. Fixed in tests.
    public var random: @Sendable () -> Double

    public init(
        maxAttempts: Int = 3,
        baseDelay: Duration = .milliseconds(500),
        maxDelay: Duration = .seconds(30),
        jitter: Double = 0.2,
        retryableStatuses: Set<Int> = [429, 502, 503, 504],
        retriesNonIdempotent: Bool = false,
        maxRetryAfter: Duration = .seconds(60),
        sleeper: Sleeper = .live,
        random: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) }
    ) {
        self.maxAttempts = max(1, maxAttempts)
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.jitter = min(max(jitter, 0), 1)
        self.retryableStatuses = retryableStatuses
        self.retriesNonIdempotent = retriesNonIdempotent
        self.maxRetryAfter = maxRetryAfter
        self.sleeper = sleeper
        self.random = random
    }

    /// Three attempts, half a second then a second apart.
    public static let `default` = RetryPolicy()
    /// One attempt.
    public static let none = RetryPolicy(maxAttempts: 1)

    /// URL-loading failures worth another try: the host or its name couldn't be reached this
    /// once. `.timedOut` is retried too. `.offline` (no connection, or it dropped) isn't — the
    /// next attempt a moment later would fail the same way.
    public static let transientErrors: Set<URLError.Code> = [
        .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .secureConnectionFailed,
    ]

    // MARK: - Deciding

    /// Whether `attempt` (1-based) failing with `error` gets another try.
    public func shouldRetry(_ error: NetworkError, method: HTTPMethod, attempt: Int) -> Bool {
        guard attempt < maxAttempts, method.isIdempotent || retriesNonIdempotent else { return false }
        switch error {
        case .http(let status, _, _, _): return retryableStatuses.contains(status)
        case .timedOut: return true
        case .transport(let error): return Self.transientErrors.contains(error.code)
        case .offline, .cancelled, .invalidURL, .decoding: return false
        }
    }

    /// How long to wait after `attempt` failed: the server's `Retry-After` if it gave one,
    /// else `baseDelay × 2^(attempt−1)`, capped, with jitter.
    public func delay(afterAttempt attempt: Int, retryAfter: Duration?) -> Duration {
        if let retryAfter { return retryAfter }
        let exponent = Double(max(0, attempt - 1))
        let backoff = min(seconds(baseDelay) * pow(2, exponent), seconds(maxDelay))
        let spread = 1 + jitter * (random() * 2 - 1)
        return .milliseconds(Int((backoff * spread * 1000).rounded()))
    }

    /// `Retry-After` as seconds ("120") or an HTTP date ("Wed, 21 Oct 2026 07:28:00 GMT").
    public static func retryAfter(_ value: String?, now: Date = Date()) -> Duration? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        if let seconds = Int(value) { return .seconds(max(0, seconds)) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: value) else { return nil }
        return .milliseconds(Int(max(0, date.timeIntervalSince(now)) * 1000))
    }

    private func seconds(_ duration: Duration) -> Double {
        let (seconds, attoseconds) = duration.components
        return Double(seconds) + Double(attoseconds) / 1e18
    }
}
