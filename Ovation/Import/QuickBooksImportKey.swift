// ovation#68. The key an imported row is written under: the file it came from,
// the row exactly as it stood in that file, and the version of the importer that
// read it.
//
// ALL THREE, because each one answers a different way an import goes wrong. The
// file and the row make re-running the same import harmless: an import that is
// interrupted and started again finds what it already wrote rather than writing it
// twice. The IMPORTER VERSION is the part that is easy to leave out and the reason
// this works at all: the format is unverified, so the likeliest outcome of a first
// import is one that succeeds and is wrong, and a corrected parser has to be able
// to run again over the same file. Its version makes it a different key, so the
// first bad import does not block the fixed one forever (L121).
//
// THE KEY IS RECOMPUTABLE FROM THE IMPORT ITSELF. The file is identified by its
// contents hashed, never by its name or where it sits, because a key derived by
// asking something outside the data stops resolving when that thing moves (L565).
// The row is the RAW row, before any unquoting or reading (see `QuickBooksCSV`).
//
// ONE RECORD CAN COME FROM SEVERAL ROWS. An invoice is its row in the invoice
// list, its lines in the sales lines file and its payments in the payments report,
// and each of those rows is part of its key: an invoice whose lines changed is a
// different invoice to import even though its own row did not move. The rows are
// taken in the order given, which the import fixes as file order.
//
// THE VALUE NAMES THE VERSION IN CLEAR, so a person reading a stored key can tell
// which importer wrote it without recomputing anything.
import Foundation

struct QuickBooksImportKey: Hashable, Sendable {

    /// The importer's version. RAISE IT WHENEVER WHAT THE IMPORTER WRITES FROM A ROW
    /// CHANGES, so a corrected import is a different key and can re-run over the
    /// same files once the earlier batch is reverted (ovation#70).
    static let importerVersion = 1

    /// One row as it stood in its file.
    struct Source: Hashable, Sendable {
        /// The whole file's contents, hashed.
        let fileSHA256: String
        /// Where the row sits in that file, as a spreadsheet numbers it. PART OF THE
        /// KEY (review of 1e824ef, L186): two payments of the same amount on the same
        /// day read as the same text, and without their place the second's key is the
        /// first's. It is still recomputable from the import, because the file it is
        /// counted in is pinned by `fileSHA256`.
        let row: Int
        /// The row exactly as the file wrote it, hashed.
        let rawRowSHA256: String
    }

    /// What is stored on the imported record.
    let value: String

    init(version: Int = importerVersion, sources: [Source]) {
        let joined = sources.map { "\($0.fileSHA256):\($0.row):\($0.rawRowSHA256)" }.joined(separator: "\n")
        value = "quickbooks-v\(version):" + QuickBooksCustodyFile.sha256(of: Data(joined.utf8))
    }
}
