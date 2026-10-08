import Foundation

/// Bounded exponential delay calculations. Retry numbers are zero-based: the
/// first retry is `0`, the second retry is `1`, and so on.
public struct RetryDelayPolicy: Equatable, Sendable {
    private static let largestNanosecondDelay = TimeInterval(UInt64.max / 1_000_000_000)

    public let baseDelay: TimeInterval
    public let multiplier: Double
    public let maximumBackoffDelay: TimeInterval
    public let maximumServerDelay: TimeInterval

    public init(
        baseDelay: TimeInterval = 1,
        multiplier: Double = 2,
        maximumBackoffDelay: TimeInterval = 8,
        maximumServerDelay: TimeInterval = 60
    ) {
        self.baseDelay = Self.bounded(baseDelay)
        self.multiplier = multiplier.isNaN ? 1 : max(1, multiplier)
        self.maximumBackoffDelay = Self.bounded(maximumBackoffDelay)
        self.maximumServerDelay = Self.bounded(maximumServerDelay)
    }

    public func exponentialDelay(retryNumber: Int, delayMultiplier: Double = 1) -> TimeInterval {
        let value = baseDelay * max(0, delayMultiplier) * pow(multiplier, Double(max(0, retryNumber)))
        guard value.isFinite else { return maximumBackoffDelay }
        return min(max(0, value), maximumBackoffDelay)
    }

    public func delay(
        retryNumber: Int,
        delayMultiplier: Double = 1,
        serverSuggestedDelay: TimeInterval? = nil
    ) -> TimeInterval {
        if let serverSuggestedDelay, serverSuggestedDelay.isFinite {
            return min(max(0, serverSuggestedDelay), maximumServerDelay)
        }
        return exponentialDelay(retryNumber: retryNumber, delayMultiplier: delayMultiplier)
    }

    public func nanoseconds(
        retryNumber: Int,
        delayMultiplier: Double = 1,
        serverSuggestedDelay: TimeInterval? = nil
    ) -> UInt64 {
        let seconds = delay(
            retryNumber: retryNumber,
            delayMultiplier: delayMultiplier,
            serverSuggestedDelay: serverSuggestedDelay
        )
        if seconds >= Self.largestNanosecondDelay {
            return UInt64.max / 1_000_000_000 * 1_000_000_000
        }
        return UInt64(seconds * 1_000_000_000)
    }

    private static func bounded(_ value: TimeInterval) -> TimeInterval {
        guard !value.isNaN else { return 0 }
        return min(max(0, value), largestNanosecondDelay)
    }
}

/// Parses numeric and HTTP-date Retry-After values and common epoch reset headers.
public enum ServerRetryDelay {
    public static func parse(
        headers: HTTPHeaders,
        now: Date = Date(),
        retryAfterHeader: String = "Retry-After",
        resetHeader: String? = nil
    ) -> TimeInterval? {
        if let value = headers[retryAfterHeader] {
            if let seconds = TimeInterval(value) {
                return seconds
            }
            if let date = httpDate(value) {
                return max(0, date.timeIntervalSince(now))
            }
        }

        guard let resetHeader,
              let value = headers[resetHeader],
              let resetAt = TimeInterval(value)
        else {
            return nil
        }
        return max(0, resetAt - now.timeIntervalSince1970)
    }

    private static func httpDate(_ value: String) -> Date? {
        let formats = [
            "EEE',' dd MMM yyyy HH':'mm':'ss z",
            "EEEE',' dd-MMM-yy HH':'mm':'ss z",
            "EEE MMM d HH':'mm':'ss yyyy",
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }
}

/// Injects time and sleeping so retry behavior can be tested without wall-clock delays.
public struct RetryScheduler: @unchecked Sendable {
    public typealias Sleep = (TimeInterval) async throws -> Void

    public static let live = RetryScheduler()

    public let now: () -> Date
    public let sleep: Sleep

    public init(
        now: @escaping () -> Date = Date.init,
        sleep: @escaping Sleep = { seconds in
            let maximumSeconds = TimeInterval(UInt64.max / 1_000_000_000)
            let boundedSeconds = seconds.isNaN ? 0 : min(max(0, seconds), maximumSeconds)
            let nanoseconds = if boundedSeconds >= maximumSeconds {
                UInt64.max / 1_000_000_000 * 1_000_000_000
            } else {
                UInt64(boundedSeconds * 1_000_000_000)
            }
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.now = now
        self.sleep = sleep
    }
}

public enum TransientNetworkFailure {
    public static func contains(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        return [
            .cannotConnectToHost,
            .dnsLookupFailed,
            .networkConnectionLost,
            .notConnectedToInternet,
            .timedOut,
        ].contains(urlError.code)
    }
}
