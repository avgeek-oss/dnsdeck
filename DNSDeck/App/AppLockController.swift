import AvgeekLocalizationCore
import Combine
import LocalAuthentication
import SwiftUI

@MainActor
final class AppLockController: ObservableObject {
    static let shared = AppLockController()

    enum Timeout: Int, CaseIterable, Identifiable {
        case never = 0
        case fiveMinutes = 300
        case tenMinutes = 600
        case fifteenMinutes = 900
        case thirtyMinutes = 1800

        var id: Self {
            self
        }

        func displayName(localizedBy localize: AppLocalizationResolver) -> String {
            switch self {
            case .never: localize("Not enforced")
            case .fiveMinutes: localize("5 minutes")
            case .tenMinutes: localize("10 minutes")
            case .fifteenMinutes: localize("15 minutes")
            case .thirtyMinutes: localize("30 minutes")
            }
        }

        var interval: TimeInterval {
            TimeInterval(rawValue)
        }
    }

    private enum StorageKeys {
        static let autoLockEnabled = UITestConfiguration.storageKey("dnsdeck.security.autoLockEnabled")
        static let autoLockTimeout = UITestConfiguration.storageKey("dnsdeck.security.autoLockTimeout")
        static let isLocked = UITestConfiguration.storageKey("dnsdeck.security.isLocked")
    }

    @Published private(set) var isLocked = false

    @Published private(set) var wasManuallyLocked = false

    @Published var timeout: Timeout {
        didSet {
            guard timeout != oldValue else { return }
            userDefaults.set(timeout.rawValue, forKey: StorageKeys.autoLockTimeout)
            if timeout == .never {
                backgroundTimestamp = nil
                stopInactivityMonitoring()
            } else {
                if backgroundTimestamp == nil {
                    backgroundTimestamp = Date()
                }
                if !isLocked {
                    startInactivityMonitoring()
                }
            }
            isAutoLockEnabled = timeout != .never
        }
    }

    @Published var isAutoLockEnabled = false

    private let userDefaults: UserDefaults
    private var backgroundTimestamp: Date?
    private var inactivityTimer: Timer?
    private var lastUserActivity: Date?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let storedTimeout = Timeout(rawValue: userDefaults.integer(forKey: StorageKeys.autoLockTimeout)),
           storedTimeout != .never || userDefaults.object(forKey: StorageKeys.autoLockTimeout) != nil
        {
            timeout = storedTimeout
        } else {
            let legacyEnabled = userDefaults.bool(forKey: StorageKeys.autoLockEnabled)
            timeout = legacyEnabled ? .fiveMinutes : .never
        }

        isAutoLockEnabled = timeout != .never

        if isAutoLockEnabled {
            isLocked = true
            userDefaults.set(true, forKey: StorageKeys.isLocked)
            userDefaults.synchronize()
        }

        startInactivityMonitoring()
    }

    var supportsBiometrics: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    func handleScenePhaseChange(_ newPhase: ScenePhase) {
        guard isAutoLockEnabled else { return }
        switch newPhase {
        case .background:
            backgroundTimestamp = Date()
            stopInactivityMonitoring()
        case .active:
            evaluateLockIfNeeded()
            startInactivityMonitoring()
        default:
            break
        }
    }

    func registerUserActivity() {
        guard isAutoLockEnabled else { return }
        Task { @MainActor in
            self.lastUserActivity = Date()
            self.restartInactivityTimer()
        }
    }

    func evaluateLockIfNeeded() {
        guard isAutoLockEnabled else { return }
        guard let timestamp = backgroundTimestamp else { return }
        let elapsed = Date().timeIntervalSince(timestamp)
        if elapsed >= timeout.interval {
            isLocked = true
            userDefaults.set(true, forKey: StorageKeys.isLocked)
            userDefaults.synchronize()
            #if os(macOS)
            NotificationCenter.default.post(name: .init("DNSLockStateChanged"), object: nil)
            #endif
        }
        backgroundTimestamp = nil
    }

    func triggerManualLock() {
        wasManuallyLocked = true
        isLocked = true
        userDefaults.set(true, forKey: StorageKeys.isLocked)
        userDefaults.synchronize()
        stopInactivityMonitoring()
        #if os(macOS)
        NotificationCenter.default.post(name: .init("DNSLockStateChanged"), object: nil)
        #endif
    }

    func requestUnlock() async -> Bool {
        guard isLocked else { return true }

        let context = LAContext()
        context.localizedFallbackTitle = ""
        let reason = "Authenticate to unlock DNSDeck"
        let policy: LAPolicy = supportsBiometrics ? .deviceOwnerAuthenticationWithBiometrics :
            .deviceOwnerAuthentication

        let success: Bool
        do {
            success = try await evaluateAuthentication(context: context, policy: policy, reason: reason)
        } catch {
            Logger.logError(error, context: "App unlock failed")
            return false
        }

        if success {
            isLocked = false
            wasManuallyLocked = false
            userDefaults.set(false, forKey: StorageKeys.isLocked)
            userDefaults.synchronize()
            startInactivityMonitoring()
            #if os(macOS)
            NotificationCenter.default.post(name: .init("DNSLockStateChanged"), object: nil)
            #endif
        }

        return success
    }

    private func evaluateAuthentication(
        context: LAContext,
        policy: LAPolicy,
        reason: String
    ) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(policy, localizedReason: reason) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    private func startInactivityMonitoring() {
        guard isAutoLockEnabled, timeout != .never else { return }
        guard !isLocked else { return } // Don't start monitoring if already locked
        lastUserActivity = Date()
        restartInactivityTimer()
    }

    private func stopInactivityMonitoring() {
        inactivityTimer?.invalidate()
        inactivityTimer = nil
    }

    private func restartInactivityTimer() {
        guard isAutoLockEnabled, timeout != .never else { return }

        inactivityTimer?.invalidate()

        inactivityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.checkInactivity()
            }
        }
    }

    private func checkInactivity() {
        guard let lastActivity = lastUserActivity else { return }
        guard timeout != .never else { return }
        let elapsed = Date().timeIntervalSince(lastActivity)
        if elapsed >= timeout.interval {
            triggerManualLock()
        }
    }
}
