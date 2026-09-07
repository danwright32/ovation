// Plan 1.9, ovation#58. THE LIST of everything in Ovation that can reach live
// data, and the refusal each one carries under a disposable launch.
//
// WHY A LIST AT ALL. Each resolver already refuses on its own, which is the
// structural half: the wrong thing cannot be written rather than being
// discouraged (L2, L196). What no individual resolver can do is notice that a
// NEW one was added without a refusal. This is the register that notices, and
// `scripts/check-isolation-floor.sh` fails a push where a live resolver exists
// in the sources and is not named here (L96, L247).
//
// IT NAMES WHAT IS NOT BUILT YET, and that is the part plan 1.9 insists on: the
// floor is "extended explicitly in each later milestone rather than by whoever
// notices". Each entry below that has no resolver carries the issue that will
// add one, so the gap is visible rather than absent from a list nobody
// maintains.
//
// THE MEASUREMENT THAT SETS THE SIZE OF THIS. Overture's Gmail, OAuth and reply
// detection sources contain ZERO occurrences of any test refusal across all 15
// files and 2,230 lines, and plan 5.0 vendors seven of them whole file into
// Ovation. A test exercising the intake path with Dan's real token on disk talks
// to his real mailbox, and under the gmail.modify route relabels his real
// receipts. A test write into either consumed identifier ledger is equally
// unrecoverable: it permanently suppresses that booking's invoice or that
// message's receipt.
import Foundation

enum LiveDataFloor {
    /// One live thing Ovation can reach.
    struct Entry: Sendable {
        /// The resolver's own name, matched against the sources by
        /// `scripts/check-isolation-floor.sh`.
        let name: String
        /// What it reaches, in plain words.
        let reaches: String
        /// How to ask it for the live location. Nil when nothing has built it.
        let resolve: (@Sendable () -> URL?)?
        /// The issue that will build it. Nil once it is built.
        let issue: String?
    }

    static let entries: [Entry] = [
        // BUILT. Each returns nil under a disposable launch, and the default
        // arguments read this process, so a caller that passes nothing is
        // refused rather than handed the real path.
        .init(name: "liveStoreURL",
              reaches: "the SwiftData store holding seven years of tax records",
              resolve: { StoreLocation.liveStoreURL() }, issue: nil),
        .init(name: "liveBookingQueueDirectory",
              reaches: "the queue Downbeat writes and Ovation drains BY DELETING",
              resolve: { StoreLocation.liveBookingQueueDirectory() }, issue: nil),
        .init(name: "liveRoot",
              reaches: "the documents folder holding every receipt and sent PDF",
              resolve: { DocumentStore.liveRoot() }, issue: nil),
        .init(name: "liveURL",
              reaches: "the problems journal, the record of every failure reported",
              resolve: { FileProblemsJournal.liveURL() }, issue: nil),

        // NOT BUILT. Named now so the floor is extended by this list rather than
        // by whoever notices, and so a later milestone inherits the requirement
        // instead of rediscovering it.
        .init(name: "liveGmailClient",
              reaches: "Dan's real mailbox. Under the gmail.modify route it relabels "
                + "his real receipts, which is not recoverable",
              resolve: nil, issue: "ovation#76"),
        .init(name: "liveCredentialStore",
              reaches: "the 0600 token file holding a refresh token with send and modify rights",
              resolve: nil, issue: "ovation#76"),
        .init(name: "liveConsumedBookingLedger",
              reaches: "the record of which bookings were invoiced. A test write "
                + "permanently suppresses that booking's invoice",
              resolve: nil, issue: "ovation#31"),
        .init(name: "liveConsumedMessageLedger",
              reaches: "the record of which messages were filed. A test write "
                + "permanently suppresses that message's receipt",
              resolve: nil, issue: "ovation#79"),
        .init(name: "liveExportRunRecord",
              reaches: "the record of when the export last ran. A test written success "
                + "makes the staleness report permanently unraisable",
              resolve: nil, issue: "ovation#64"),
        .init(name: "liveExportDirectory",
              reaches: "the folder the CSVs are written to. A test naming it writes "
                + "over whatever is there",
              resolve: nil, issue: "ovation#61"),
        .init(name: "liveBackupsDirectory",
              reaches: "the folder Dan chooses for backups, which on this Mac may sync "
                + "to a Synology",
              resolve: nil, issue: "ovation#87"),
    ]

    /// The ones that exist today and can therefore be asked.
    static var built: [Entry] { entries.filter { $0.resolve != nil } }

    /// The ones a later milestone owes a refusal.
    static var pending: [Entry] { entries.filter { $0.resolve == nil } }
}
