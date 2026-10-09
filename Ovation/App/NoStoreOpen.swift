// ovation#657. What a menu entry says when this launch has no store open.
//
// ONE SENTENCE, READ BY EVERY ENTRY IT GREYS: the year end export, drafting from
// the booking queue, and the invoice entries in the Edit menu. Each used to carry
// its own copy, worded around what it would have done ("nothing to export from",
// "nowhere to put a draft"), and a comment claiming two copies say the same thing
// is a claim nothing checks (L370, L41). The entry's own title already says what
// it does, so the sentence only has to say why it cannot, and that is the same
// for all of them (L118).
//
// It names the store because that is the only way any of these ends up with
// nothing to run: the app builds every writer from the open store, and builds
// none where this launch has no store (`OvationApp`, `opened.map`).
enum NoStoreOpen {
    static let sentence = "There is no store open on this launch. "
        + "The launch sequence either refused or has not run."
}
