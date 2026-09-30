import Foundation
import Security

@MainActor
public protocol XUsernameSharingClock: Sendable {
    var now: Date { get }
    var monotonicNow: TimeInterval { get }
    func sleep(for seconds: TimeInterval) async throws
}

@MainActor
public struct SystemXUsernameSharingClock: XUsernameSharingClock {
    private let anchor = ContinuousClock.now
    public init() {}
    public var now: Date { Date() }
    public var monotonicNow: TimeInterval {
        let elapsed = anchor.duration(to: ContinuousClock.now).components
        return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
    }
    public func sleep(for seconds: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(max(0, seconds)))
    }
}

public enum XUsernameSharingChoice: String, Codable, Sendable { case unknown, acknowledged, declined }

/// The durable file contains grants and withdrawal work only; observed usernames never enter it.
@MainActor
public final class XUsernameSharingCoordinator {
    nonisolated public static let disclosureVersion = "x-username-feedback-v1"
    nonisolated public static let disclosure = "Slop Factory stores your X username to count distinct users and users active in the last 30 days. We may send you a direct message on X to ask about your experience with Slop Factory. We do not collect your X password, cookies, or login tokens for this purpose."
    nonisolated public static let scopeText = "This choice applies to X accounts you use in this installation of Slop Factory. You can change it from X username sharing in the menu."
    public private(set) var generation = UUID()
    public private(set) var lastDiagnostic: String?
    public var onChange: (() -> Void)?
    private struct Grant: Codable {
        var id: UUID
        var capability: String
        var version: String
        var destination: String
        var key: String
        var sequence: Int64 = 0
        var withdrawalFailures: Int?
        var nextWithdrawalAt: Date?
        var permanentWithdrawalError: Bool?
    }
    private struct State: Codable {
        var format = 1
        var choice = XUsernameSharingChoice.unknown
        var version = XUsernameSharingCoordinator.disclosureVersion
        var time: Date?
        var destination: String?
        var grant: Grant?
        var withdrawals: [Grant] = []
    }
    private struct Window { var popup: Bool; var current: String?; var lastReported: String?; var revision = UUID() }
    private var state = State()
    private var readable = true
    private var disabled = false
    private var configuration: XHandleRegistrationConfiguration?
    private let transport: any XHandleRegistrationTransport
    private let stateURL: URL?
    private let clock: any XUsernameSharingClock
    private var windows: [UUID: Window] = [:]
    private struct Event {
        var window: UUID
        var revision: UUID
        var handle: String
        var generation: UUID
        var deadline: TimeInterval
    }
    private var events: [Event] = []
    private var unsavedChoice = false
    private var activityRequest: Task<XHandleRegistrationResponse, Error>?
    private var activityWindow: UUID?
    private var activityToken: UUID?
    private var retrySleep: Task<Void, Error>?
    private var draining: UUID?
    private var withdrawing = false
    private var withdrawalTimer: Task<Void, Never>?
    private var expirationTimer: Task<Void, Never>?

    public var choice: XUsernameSharingChoice {
        guard readable, state.version == Self.disclosureVersion, state.destination == configuration?.projectURL.absoluteString else { return .unknown }
        return state.choice
    }
    public var choiceTime: Date? { state.time }
    public var collectionEnabled: Bool { readable && !disabled && configuration != nil && choice == .acknowledged && state.grant != nil }
    public var statusText: String {
        if let lastDiagnostic {
            return state.withdrawals.isEmpty ? lastDiagnostic : lastDiagnostic + " Removing feedback contact permission when a connection is available."
        }
        if choice == .acknowledged && collectionEnabled {
            if pendingWithdrawalForCurrentDestination { return "Waiting to remove the previous sharing permission before reporting with your new choice." }
            return "X username sharing is on for this installation."
        }
        return state.withdrawals.isEmpty ? "Sharing is off on this Mac." : "Sharing is off on this Mac. Removing feedback contact permission when a connection is available."
    }

    public init(configuration: XHandleRegistrationConfiguration?, transport: any XHandleRegistrationTransport = URLSessionXHandleRegistrationTransport(), stateURL: URL? = nil, legacyStateURL: URL? = nil, clock: any XUsernameSharingClock = SystemXUsernameSharingClock()) {
        self.configuration = configuration
        self.clock = clock
        self.transport = transport
        self.stateURL = stateURL
        do {
            if let legacyStateURL, FileManager.default.fileExists(atPath: legacyStateURL.path) { try FileManager.default.removeItem(at: legacyStateURL) }
            if let stateURL, FileManager.default.fileExists(atPath: stateURL.path) {
                state = try JSONDecoder().decode(State.self, from: Data(contentsOf: stateURL))
                guard state.format == 1, Self.valid(state) else { throw CocoaError(.fileReadCorruptFile) }
            }
        } catch {
            readable = false
            lastDiagnostic = "X username sharing is disabled. Local sharing state needs repair; existing withdrawal information has been preserved."
        }
        if readable, let configuration {
            let destination = configuration.projectURL.absoluteString
            if state.grant?.destination == destination { state.grant?.key = configuration.publishableKey }
            for index in state.withdrawals.indices where state.withdrawals[index].destination == destination {
                state.withdrawals[index].key = configuration.publishableKey
            }
        }
        // A permanent error gets one new attempt in this launch, never a hot loop.
        for index in state.withdrawals.indices where state.withdrawals[index].permanentWithdrawalError == true {
            state.withdrawals[index].permanentWithdrawalError = nil
            state.withdrawals[index].nextWithdrawalAt = nil
        }
        if readable && (state.version != Self.disclosureVersion || state.destination != configuration?.projectURL.absoluteString), let grant = state.grant {
            var candidate = state
            candidate.withdrawals.append(grant)
            candidate.grant = nil
            candidate.choice = .unknown
            if save(candidate) { state = candidate } else { disabled = true }
        }
    }

    nonisolated private static func valid(_ state: State) -> Bool {
        func validGrant(_ grant: Grant) -> Bool {
            grant.sequence >= 0 && (grant.withdrawalFailures ?? 0) >= 0 && (grant.withdrawalFailures ?? 0) <= 3 && !grant.version.isEmpty && grant.version.utf8.count <= 128 && grant.capability.utf8.count == 64 && grant.capability.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } && XHandleRegistrationConfiguration(projectURL: grant.destination, publishableKey: grant.key) != nil
        }
        guard state.withdrawals.allSatisfy(validGrant), state.grant.map(validGrant) ?? true else { return false }
        let ids = state.withdrawals.map(\.id) + (state.grant.map { [$0.id] } ?? [])
        guard Set(ids).count == ids.count else { return false }
        if state.choice == .declined && state.grant != nil { return false }
        if state.choice != .unknown && state.time == nil { return false }
        if state.choice == .acknowledged {
            guard let grant = state.grant, grant.destination == state.destination, grant.version == state.version else { return false }
        }
        return true
    }

    private func save(_ candidate: State) -> Bool {
        guard readable else { return false }
        guard let stateURL else { return true }
        do {
            let directory = stateURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let temporary = directory.appendingPathComponent(".sharing-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
            let handle = try FileHandle(forWritingTo: temporary)
            try handle.write(contentsOf: JSONEncoder().encode(candidate))
            try handle.synchronize()
            try handle.close()
            guard rename(temporary.path, stateURL.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
            let descriptor = open(directory.path, O_RDONLY)
            guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
            defer { close(descriptor) }
            guard fsync(descriptor) == 0 else { throw CocoaError(.fileWriteUnknown) }
            if !unsavedChoice { lastDiagnostic = nil }
            return true
        } catch {
            lastDiagnostic = "X username sharing preference could not be saved. Sharing remains off in this process; this change may not survive restart."
            return false
        }
    }

    @discardableResult public func acknowledge() -> Bool {
        guard readable, let configuration else { disabled = true; onChange?(); return false }
        if collectionEnabled { return true }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            lastDiagnostic = "X username sharing could not create a secure grant. Try again."; return false
        }
        var candidate = state
        if let old = candidate.grant { candidate.withdrawals.append(old) }
        candidate.choice = .acknowledged
        candidate.version = Self.disclosureVersion
        candidate.time = clock.now
        candidate.destination = configuration.projectURL.absoluteString
        candidate.grant = Grant(id: UUID(), capability: bytes.map { String(format: "%02x", $0) }.joined(), version: Self.disclosureVersion, destination: configuration.projectURL.absoluteString, key: configuration.publishableKey)
        guard save(candidate) else { disabled = true; onChange?(); return false }
        state = candidate; unsavedChoice = false; lastDiagnostic = nil; disabled = false; generation = UUID()
        for id in windows.keys { windows[id]?.lastReported = nil; windows[id]?.current = nil }
        scheduleWithdrawal()
        onChange?()
        return true
    }

    public func updateConfiguration(_ configuration: XHandleRegistrationConfiguration?) async {
        let oldConfiguration = self.configuration
        let changedDestination = oldConfiguration?.projectURL != configuration?.projectURL
        let changedKey = oldConfiguration?.publishableKey != configuration?.publishableKey
        if changedDestination || configuration == nil { stopCollection() }
        self.configuration = configuration
        guard readable else { onChange?(); return }
        var candidate = state
        if let grant = candidate.grant,
           grant.destination != configuration?.projectURL.absoluteString || grant.version != Self.disclosureVersion {
            candidate.withdrawals.append(grant)
            candidate.grant = nil
            candidate.choice = .unknown
        }
        if let configuration {
            let destination = configuration.projectURL.absoluteString
            if candidate.grant?.destination == destination { candidate.grant?.key = configuration.publishableKey }
            for index in candidate.withdrawals.indices where candidate.withdrawals[index].destination == destination {
                let repairedStoredKey = candidate.withdrawals[index].key != configuration.publishableKey
                candidate.withdrawals[index].key = configuration.publishableKey
                if repairedStoredKey || changedKey || changedDestination {
                    candidate.withdrawals[index].permanentWithdrawalError = nil
                    candidate.withdrawals[index].nextWithdrawalAt = nil
                }
            }
        }
        guard save(candidate) else { stopCollection(); return }
        state = candidate
        onChange?()
        await resume()
    }

    public func openWindow(id: UUID, isPopup: Bool = false) { windows[id] = Window(popup: isPopup) }
    public func closeWindow(id: UUID) { windows.removeValue(forKey: id); events.removeAll { $0.window == id }; if activityWindow == id { activityRequest?.cancel(); retrySleep?.cancel() } }

    public func observe(handle: String?, origin: URL, isMainFrame: Bool, windowID: UUID, generation: UUID) async {
        guard collectionEnabled, generation == self.generation, isMainFrame, XHandleValidation.isTrustedOrigin(origin), var window = windows[windowID], !window.popup else { return }
        let normalized = handle.flatMap(XHandleValidation.normalize)
        if window.current != normalized { window.revision = UUID(); events.removeAll { $0.window == windowID }; if activityWindow == windowID { activityRequest?.cancel(); retrySleep?.cancel() } }
        window.current = normalized
        windows[windowID] = window
        guard let normalized, normalized != window.lastReported else { return }
        windows[windowID]?.lastReported = normalized
        events.append(Event(window: windowID, revision: window.revision, handle: normalized, generation: generation, deadline: clock.monotonicNow + 30))
        if draining != nil || pendingWithdrawalForCurrentDestination { scheduleEventExpiration() }
        await drain()
        scheduleEventExpiration()
    }

    private func eligible(_ event: Event) -> Bool {
        collectionEnabled && generation == event.generation && windows[event.window]?.current == event.handle && windows[event.window]?.revision == event.revision && clock.monotonicNow < event.deadline
    }

    private var pendingWithdrawalForCurrentDestination: Bool {
        state.withdrawals.contains { $0.destination == configuration?.projectURL.absoluteString }
    }

    private func drain() async {
        guard draining == nil else { return }
        let token = UUID()
        draining = token
        defer {
            if draining == token { draining = nil }
            scheduleEventExpiration()
        }
        if pendingWithdrawalForCurrentDestination { await resume() }
        while draining == token && !events.isEmpty {
            events.removeAll { !eligible($0) }
            guard !events.isEmpty, !pendingWithdrawalForCurrentDestination else { return }
            let event = events.removeFirst()
            await report(event)
        }
    }

    private func report(_ event: Event) async {
        guard var grant = state.grant, grant.sequence < Int64.max, let configuration else { return }
        let normalized = event.handle
        let generation = event.generation
        grant.sequence += 1
        var candidate = state; candidate.grant = grant
        guard save(candidate) else { disabled = true; onChange?(); return }
        state = candidate
        let payload: [String: Any] = ["p_grant_id": grant.id.uuidString, "p_capability": grant.capability, "p_disclosure_version": grant.version, "p_sequence": grant.sequence, "p_handle": normalized]
        for attempt in 0...1 {
            guard eligible(event), state.grant?.id == grant.id else { return }
            var retryDelay: TimeInterval?
            do {
                var reportRequest = request(configuration: configuration, rpc: "report_x_activity_v1", payload: payload)
                reportRequest.timeoutInterval = min(15, event.deadline - clock.monotonicNow)
                let transport = self.transport
                let task = Task { try await transport.submit(reportRequest) }
                let token = UUID()
                activityToken = token; activityRequest = task; activityWindow = event.window
                defer {
                    if activityToken == token { activityRequest = nil; activityWindow = nil; activityToken = nil }
                }
                let response = try await task.value
                guard eligible(event), state.grant?.id == grant.id else { return }
                let status = (try? JSONSerialization.jsonObject(with: response.body) as? [String: String])?["status"]
                if (200..<300).contains(response.statusCode), status == "withdrawn" {
                    stopCollection()
                    lastDiagnostic = "Sharing is off because this grant was withdrawn. Acknowledge again to create a new grant."
                    onChange?(); return
                }
                if (200..<300).contains(response.statusCode), ["recorded", "duplicate"].contains(status ?? "") { return }
                if response.statusCode == 408 || response.statusCode == 429 || (500..<600).contains(response.statusCode) {
                    retryDelay = max(5, response.retryAfterDelay(relativeTo: clock.now) ?? 0)
                }
            } catch {
                guard eligible(event), self.generation == generation else { return }
                retryDelay = 5
            }
            guard attempt == 0, let retryDelay, clock.monotonicNow + retryDelay < event.deadline else { break }
            let clock = self.clock
            let sleep = Task { try await clock.sleep(for: retryDelay) }
            retrySleep = sleep; activityWindow = event.window
            do { try await sleep.value } catch { return }
            if self.generation == generation { retrySleep = nil; activityWindow = nil }
        }

        onChange?()
    }

    public func stopCollection() {
        disabled = true; generation = UUID(); events.removeAll(); activityRequest?.cancel(); retrySleep?.cancel(); draining = nil
        expirationTimer?.cancel(); expirationTimer = nil
        for id in windows.keys { windows[id]?.current = nil; windows[id]?.lastReported = nil }
        onChange?()
    }

    @discardableResult public func decline() async -> Bool {
        stopCollection()
        var candidate = state
        if let grant = candidate.grant { candidate.withdrawals.append(grant) }
        candidate.grant = nil
        candidate.choice = .declined; candidate.version = Self.disclosureVersion
        candidate.destination = configuration?.projectURL.absoluteString; candidate.time = clock.now
        guard save(candidate) else { unsavedChoice = true; onChange?(); return false }
        state = candidate; unsavedChoice = false; lastDiagnostic = nil; onChange?()
        await resume()
        return true
    }

    public func resume() async {
        guard readable, !withdrawing else { return }
        withdrawing = true
        withdrawalTimer?.cancel(); withdrawalTimer = nil
        for grant in state.withdrawals {
            guard grant.permanentWithdrawalError != true,
                  grant.nextWithdrawalAt.map({ $0 <= clock.now }) ?? true,
                  let config = XHandleRegistrationConfiguration(projectURL: grant.destination, publishableKey: grant.key) else { continue }
            var confirmed = false
            var permanent = false
            var retryAfter: TimeInterval = 0
            do {
                let response = try await transport.submit(request(configuration: config, rpc: "withdraw_x_sharing_v1", payload: ["p_grant_id": grant.id.uuidString, "p_capability": grant.capability, "p_disclosure_version": grant.version]))
                let status = (try? JSONSerialization.jsonObject(with: response.body) as? [String: String])?["status"]
                confirmed = (200..<300).contains(response.statusCode) && status == "withdrawn"
                permanent = (400..<500).contains(response.statusCode) && response.statusCode != 408 && response.statusCode != 429
                retryAfter = response.retryAfterDelay(relativeTo: clock.now) ?? 0
            } catch { /* Only the withdrawal outbox survives a connectivity failure. */ }
            var candidate = state
            if confirmed {
                candidate.withdrawals.removeAll { $0.id == grant.id }
                if save(candidate) { state = candidate; continue }
            }
            guard let index = state.withdrawals.firstIndex(where: { $0.id == grant.id }) else { continue }
            // A repaired key must get its own attempt; an older response cannot mark it permanent.
            guard state.withdrawals[index].key == grant.key else { continue }
            candidate = state
            let failures = candidate.withdrawals[index].withdrawalFailures ?? 0
            candidate.withdrawals[index].withdrawalFailures = min(failures + 1, 3)
            candidate.withdrawals[index].permanentWithdrawalError = permanent
            candidate.withdrawals[index].nextWithdrawalAt = clock.now.addingTimeInterval(max([60.0, 300, 1800][min(failures, 2)], retryAfter))
            _ = save(candidate)
            // A failed metadata save must not turn a network failure into a tight retry loop.
            state = candidate
        }
        withdrawing = false
        scheduleWithdrawal()
        onChange?()
        if !events.isEmpty { await drain() }
    }

    private func scheduleEventExpiration() {
        expirationTimer?.cancel(); expirationTimer = nil
        events.removeAll { !eligible($0) }
        guard let deadline = events.map(\.deadline).min() else { return }
        let clock = self.clock
        let delay = max(0, deadline - clock.monotonicNow)
        expirationTimer = Task { [weak self] in
            do { try await clock.sleep(for: delay); try Task.checkCancellation() } catch { return }
            self?.expirationTimer = nil
            self?.scheduleEventExpiration()
        }
    }

    private func scheduleWithdrawal() {
        withdrawalTimer?.cancel(); withdrawalTimer = nil
        var earliest: Date?
        for grant in state.withdrawals where grant.permanentWithdrawalError != true {
            let next = grant.nextWithdrawalAt ?? clock.now
            if earliest == nil || next < earliest! { earliest = next }
        }
        guard let next = earliest else { return }
        // Recheck long Retry-After dates daily without overflowing Duration.
        let delay = min(86_400, max(0, next.timeIntervalSince(clock.now)))
        let clock = self.clock
        withdrawalTimer = Task { [weak self] in
            do { try await clock.sleep(for: delay); try Task.checkCancellation() } catch { return }
            self?.withdrawalTimer = nil
            await self?.resume()
        }
    }

    private func request(configuration: XHandleRegistrationConfiguration, rpc: String, payload: [String: Any]) -> URLRequest {
        var request = URLRequest(url: configuration.projectURL.appendingPathComponent("rest/v1/rpc/" + rpc), timeoutInterval: 15)
        request.httpMethod = "POST"; request.httpShouldHandleCookies = false
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        return request
    }
}
