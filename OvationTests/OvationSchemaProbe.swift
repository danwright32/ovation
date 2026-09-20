// ovation#133. What was OBSERVED when a screen's context and an actor's context
// write the same invoice, on macOS 26.5.1.
//
// EACH ONE IS THE MEASURED VALUE, not the expected one. They were written as a
// hypothesis, run, and corrected where the run disagreed, which is the whole
// point of a probe: a pass mark written after the run has proved nothing (L246).
// Two of them disagreed, and those two are the finding.
//
// WHY THEY ARE NAMED CONSTANTS RATHER THAN LITERALS IN THE TEST. The probe reads
// as a measurement, and the pair that decides the design (`numberOnTheHeldObject`
// against `numberOnADirtyHeldObject`) sits here side by side, where the
// difference between them cannot be missed.
enum OvationSchemaProbe {

    // MARK: a context holding NO unsaved changes of its own

    /// Fetching again in the context that is already holding the row.
    static let numberAfterPlainRefetch: Int64? = 1_123
    /// After `rollback()` discards what the context holds.
    static let numberAfterRollback: Int64? = 1_123
    /// Read through the reference the screen captured BEFORE the other write, after
    /// a fetch has been made in its context. The fetch REPAIRS the held object.
    static let numberOnTheHeldObject: Int64? = 1_123
    /// After that context then saves an edit of its own to another field, written
    /// through that held reference. The other context's write survives.
    static let numberSurvivingTheScreensSave: Int64? = 1_123

    // MARK: the same context with ONE unsaved edit on it, which is what a screen is

    /// What the screen had typed and not saved, read back after a fetch. It keeps
    /// it, so the fetch is not destructive.
    static let unsavedEditAfterAFetch: String? = "typed-but-not-saved"

    /// THE FINDING. The same fetch, on a context with a pending change, does NOT
    /// bring the other context's write in. `nil`, where a settled context gets
    /// 1,123.
    ///
    /// So "the screens re-read" is not a design that holds: it works in exactly
    /// the state where nothing was at stake and fails in the one state a screen is
    /// in while somebody is working in it.
    static let numberOnADirtyHeldObject: Int64? = nil

    /// And the save then writes that stale nil back over the allocated number,
    /// while the screen's own edit lands, so the surface reports success.
    static let numberAfterADirtySave: Int64? = nil
}
