import Foundation

/// Canonical in-memory registry of AnimalSession objects.
///
/// Every part of the app (ContentView, NetworkService, detail views) must
/// obtain session objects through this store.  That guarantees that
/// @Published changes made by NetworkService on one reference are always
/// seen by SwiftUI observers holding a different variable pointing to the
/// SAME object.
///
/// Without this, ContentView.reloadSessions() would decode a fresh instance
/// from disk on every call, and any @Published mutations that NetworkService
/// already applied to the old in-memory instance would be lost.
final class SessionStore {

    static let shared = SessionStore()
    private init() {}

    // MARK: - Internal cache

    private var cache: [String: AnimalSession] = [:]

    // MARK: - Register (call once when a new session is created)

    /// Inserts a brand-new session into the cache so NetworkService and
    /// the list view always share the same instance.
    func register(_ session: AnimalSession) {
        print("[SessionStore] register id=\(session.id) #\(session.sessionNumber)")
        cache[session.id] = session
    }

    // MARK: - Canonical look-up

    /// Returns the cached instance for `id`, or nil if not yet registered.
    func session(withID id: String) -> AnimalSession? {
        cache[id]
    }

    // MARK: - Reload from disk (use instead of AnimalSession.loadAll())

    /// Loads all sessions from disk.
    /// • If a session already exists in the cache, the existing instance is
    ///   returned (its non-@Published properties are refreshed from disk).
    /// • If the session is new (app relaunch, etc.) a fresh instance is
    ///   decoded and added to the cache.
    ///
    /// Returns sessions sorted by sessionNumber.
    @discardableResult
    func reload() -> [AnimalSession] {
        let freshFromDisk = AnimalSession.loadAll()
        print("[SessionStore] reload — \(freshFromDisk.count) sessions on disk, \(cache.count) cached")

        let result: [AnimalSession] = freshFromDisk.map { fresh in
            if let existing = cache[fresh.id] {
                // Merge disk-persisted, non-@Published fields into the live
                // instance so edits made in other flows are reflected here.
                existing.mergeNonPublished(from: fresh)

                // Only promote the network state from disk if it is "further
                // along" than what the live instance already has.
                // This prevents a stale .waiting saved during a previous run
                // from overwriting a .received state that NetworkService just
                // set on the live instance.
                if fresh.weightEstimateState.rank > existing.weightEstimateState.rank {
                    existing.weightEstimateState = fresh.weightEstimateState
                    existing.weightEstimateJSON  = fresh.weightEstimateJSON
                    print("[SessionStore]   promoted network state to \(fresh.weightEstimateState) for #\(existing.sessionNumber)")
                }

                print("[SessionStore]   reused cached instance for #\(existing.sessionNumber)")
                return existing
            } else {
                cache[fresh.id] = fresh
                print("[SessionStore]   cached new instance for #\(fresh.sessionNumber)")
                return fresh
            }
        }

        return result.sorted { $0.sessionNumber < $1.sessionNumber }
    }
}

// MARK: - WeightEstimateState ordering helper

private extension WeightEstimateState {
    /// Higher rank = more "complete" state.  Used to prevent a stale disk
    /// value from overwriting a live .received result.
    var rank: Int {
        switch self {
        case .notRequested: return 0
        case .waiting:      return 1
        case .failed:       return 2
        case .received:     return 3
        }
    }
}
