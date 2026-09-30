import Foundation

/// ovation#67. Synthetic QuickBooks exports in the MEASURED shape of the three
/// custody files, with every value invented.
///
/// THE SHAPE IS MEASURED AND THE VALUES ARE NOT (L48). ovation#66's closing
/// comments record the format, and a shape only pass over the real files on
/// 2026-09-29 (counts and pattern classes, never a value) added the rest: CRLF
/// line endings and no byte order mark; three preamble lines each padded with
/// empty columns to the header's width; a fourth line that is EMPTY, not a row
/// of commas; the header on line 5; amounts with two decimals and no currency
/// symbol in data rows, a thousands comma in some, and a dollar sign only on the
/// TOTAL and "Total for" rows; three empty lines after TOTAL; and a report
/// timestamp line whose first column carries the basis ("Cash Basis ...") on
/// the sales lines report and nothing on the other two.
///
/// The sales lines report adds its own structure: a group heading carries only
/// the product name in the first column, a nested group closes with "Total for
/// <name> with sub-items", lines with no product follow a wholly EMPTY row and
/// close with "Total for --", and those lines carry no quantity or price.
///
/// THE REPOSITORY IS PUBLIC, so every name here is invented and obviously so
/// (docs/PRIVACY-FLOOR.md). None of it may be copied from the custody files.
enum QuickBooksFixture {

    static let invoiceListHeader = "Date,Transaction type,Num,Name,Memo,Due date,Amount,Open balance"
    static let paymentsHeader = "Date,Transaction type,Num,Posting (Y/N),Name,Memo,Account name,Split,Amount"
    static let salesLinesHeader =
        ",Transaction date,Transaction type,Num,Client full name,Description,Quantity,Sales price,Amount,Balance"

    /// A whole export: preamble, header, the body lines as given, TOTAL where
    /// the report has one, three empty lines and the timestamp line.
    ///
    /// The body lines are written RAW, already quoted the way QuickBooks quotes,
    /// so a test can plant exactly the malformation it is about.
    static func export(title: String, width: Int, header: String, body: [String],
                       total: String?, basis: String = "") -> String {
        let pad = String(repeating: ",", count: width - 1)
        var lines = [
            "Fictional Photography Co" + pad,
            title + pad,
            "\"January 1-September 29, 2026\"" + pad,
            "",
            header,
        ]
        lines += body
        if let total { lines.append(total) }
        lines += ["", "", ""]
        lines.append("\"\(basis) Tuesday, September 29, 2026 09:30 PM GMT-04:00\"" + pad)
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    static func invoiceList(_ body: [String], total: String = "\"$1,234.56\"",
                            openBalance: String = "$0.00") -> String {
        export(title: "Invoice List by Date", width: 8, header: invoiceListHeader, body: body,
               total: "TOTAL,,,,,,\(total),\(openBalance)")
    }

    static func payments(_ body: [String], total: String) -> String {
        export(title: "Transaction List by Date", width: 9, header: paymentsHeader, body: body,
               total: "TOTAL,,,,,,,,\(total)")
    }

    static func salesLines(_ body: [String], total: String, basis: String = "Accrual Basis") -> String {
        export(title: "Sales by Product/Service Detail", width: 10, header: salesLinesHeader,
               body: body, total: "TOTAL,,,,,,,,\(total),", basis: basis)
    }

    static let invoicesAndPaymentsHeader = ",Date,Transaction type,Memo/Description,Transaction number,Amount"

    /// The Invoices and Received Payments report (2026-09-30). MEASURED: it
    /// groups by CLIENT under a heading row carrying only the client's name,
    /// its payments carry no transaction number, and it exports NO TOTAL row and
    /// no "Total for" rows, so the body runs straight into the three empty
    /// lines and the timestamp.
    static func invoicesAndPayments(_ body: [String], timestamp: Bool = true) -> String {
        var text = export(title: "Invoices and Received Payments", width: 6, header: invoicesAndPaymentsHeader,
                          body: body, total: nil)
        if !timestamp, let stamp = text.range(of: "\" Tuesday") {
            text = String(text[..<stamp.lowerBound])
        }
        return text
    }

    static func client(_ name: String) -> String { name + ",,,,," }

    static func ledgerInvoice(_ date: String = "1/19/2026", number: String = "1001", memo: String = "",
                              amount: String = "100.00") -> String {
        ",\(date),Invoice,\(memo),\(number),\(amount)"
    }

    static func ledgerPayment(_ date: String = "1/25/2026", amount: String = "100.00") -> String {
        ",\(date),Payment,,,\(amount)"
    }

    /// An invoice list row. The name is written as given, so a caller wanting a
    /// comma in it passes it quoted.
    static func invoice(_ date: String = "1/19/2026", number: String = "1001",
                        name: String = "Fictive Quartet", memo: String = "",
                        due: String = "2/18/2026", amount: String = "100.00",
                        open: String = "0.00") -> String {
        "\(date),Invoice,\(number),\(name),\(memo),\(due),\(amount),\(open)"
    }

    static func payment(_ date: String = "1/20/2026", name: String = "Fictive Quartet",
                        posting: String = "Yes", account: String = "Imaginary Checking",
                        amount: String = "100.00") -> String {
        "\(date),Payment,,\(posting),\(name),,\(account),Accounts Receivable (A/R),\(amount)"
    }

    static func line(_ date: String = "1/19/2026", number: String = "1001",
                     client: String = "Fictive Quartet", description: String = "Imaginary gala",
                     quantity: String = "", price: String = "", amount: String = "100.00",
                     balance: String = "100.00") -> String {
        ",\(date),Invoice,\(number),\(client),\(description),\(quantity),\(price),\(amount),\(balance)"
    }

    static func heading(_ product: String) -> String { product + ",,,,,,,,," }

    static func groupTotal(_ label: String, amount: String) -> String {
        "Total for \(label),,,,,,,,\(amount),"
    }

    /// Writes `text` to a throwaway folder under the temporary directory, never
    /// under the custody folder (plan 1.9), and answers the file it wrote.
    static func write(_ text: String, named name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "quickbooks-fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        try Data(text.utf8).write(to: url)
        return url
    }
}
