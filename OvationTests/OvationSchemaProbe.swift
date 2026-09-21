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

/// ovation#451. What a `@ModelActor`'s save tells the rest of the process, on
/// macOS 26.5.1.
///
/// SAME DISCIPLINE AS THE BLOCK ABOVE: each value was written as a hypothesis
/// before the probe ran and corrected to what the run said. The design of how the
/// invoice list re-derives rests on these, so if a system update changes one, the
/// failing test names the decision that lost its basis rather than only reporting
/// that a fact moved (L82, L175).
enum ModelSaveNoticeProbe {

    /// Whether `ModelContext.didSave` is posted at all when the saving context
    /// belongs to a `@ModelActor` rather than to a screen.
    ///
    /// If this is false, no platform signal exists and the re-read has to be
    /// driven by something Ovation owns, which every future writer can forget
    /// (L621). It is the measurement the whole shape depends on.
    static let actorSaveIsAnnounced = true

    /// The userInfo keys the notification carries.
    static let didSaveKeys: Set<String> = ["inserted", "updated", "deleted"]

    /// Whether the row the actor wrote is named under `updated`.
    ///
    /// Ovation does not need the identifiers to re-derive (it re-reads the whole
    /// list), but a notice that cannot say WHAT changed can never be narrowed
    /// later, so it is worth knowing which is true.
    static let updatedNamesTheRowWritten = true

    /// The highest invoice number a FRESH reader could see at the instant the
    /// notification was delivered, where the actor had just allocated 1123.
    ///
    /// THIS IS THE ONE THAT DECIDES CORRECTNESS. A signal delivered before its own
    /// write is readable would have every listener re-read the old answer and then
    /// sit on it, which is ovation#451 with a notification bolted on top.
    static let numberReadableWhenAnnounced: Int64? = 1_123

    /// Whether the notification's `object` is the `ModelContext` that saved, so a
    /// listener can compare its container against its own and ignore everything
    /// else in the process.
    ///
    /// If this is false the notice cannot be scoped, and a listener either
    /// re-reads on every container's writes or has to find another way to tell.
    static let noticeNamesTheStoreItCameFrom = true
}
