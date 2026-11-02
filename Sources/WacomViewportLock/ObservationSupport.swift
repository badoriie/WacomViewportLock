import Observation

/// Runs `apply` now and again every time any `@Observable` property it read changes.
/// Bridges the Observation framework into imperative AppKit code.
@MainActor
func observeContinuously(_ apply: @escaping @MainActor () -> Void) {
    withObservationTracking {
        apply()
    } onChange: {
        // `onChange` fires before the new value is stored; re-run on the next main-actor turn.
        Task { @MainActor in observeContinuously(apply) }
    }
}
