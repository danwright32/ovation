// ovation#40, PRD 5a. The roster pass, drawn.
//
// TRANSLATED FROM `docs/design/clients.html`, NOT COPIED. The design record
// names the web idioms in that file that must be translated rather than carried
// across: an action is a word with padding and no underline, the window chrome
// and traffic lights are drawn by the system, and type is the system's.
//
// ORDERED BY COST, NOT BY COUNT (Dan, 2026-09-07). One unsendable address sits
// above twenty five missing tax statuses, because frequency earns real estate on
// a list read daily and consequence earns it on a list cleared once.
//
// A SECTION WITH NOTHING IN IT IS NOT DRAWN (PRD 5a, corrected 2026-09-11). The
// design file drew both headings unconditionally, and once Dan fixed the one bad
// address at source that would have read `Addresses that cannot be sent to  0`,
// which is the rule this very screen extended to a whole place in the app.
//
// IT NAMES CLIENTS ON SCREEN AND NOWHERE ELSE. Dan reads names on his own
// screen; nothing here writes one into a log or an error (docs/PRIVACY-FLOOR.md).
import SwiftUI

struct RosterPassView: View {
    @Bindable var presenter: RosterPresenter

    /// The two section titles, held as constants because the tests that assert a
    /// section is ABSENT compare against them. That keeps those tests about the
    /// RULE rather than the wording, and one test pins the wording itself so the
    /// constant cannot quietly drift to something the design never settled.
    static let addressSectionTitle = "Addresses that cannot be sent to"
    static let taxSectionTitle = "Sales tax status"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar

            if let failure = presenter.lastFailure {
                failureBanner(failure)
            }

            if presenter.isSettled {
                settled
            } else {
                pass
            }
        }
        .background(OvationPalette.background)
    }

    // MARK: the bar across the top

    private var toolbar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Destination.roster.title)
                .font(.system(size: 22, weight: .regular, design: .serif))
                .foregroundStyle(OvationPalette.ink)
            Spacer()
            Text(presenter.isSettled
                 ? "Settled"
                 : "\(presenter.remaining) of \(presenter.rosterSize) clients")
                .font(.system(size: 12))
                .foregroundStyle(OvationPalette.quiet)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Divider().overlay(OvationPalette.rule) }
    }

    /// L415. A write that did not land says so, where the change was made.
    private func failureBanner(_ sentence: String) -> some View {
        Text(sentence)
            .font(.system(size: 12.5))
            .foregroundStyle(OvationPalette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(OvationPalette.chrome)
    }

    // MARK: nothing left

    /// Dan, 2026-09-07: a place you are standing in does not vanish underneath
    /// you. Answering the last question is the moment you most deserve to be
    /// told you finished.
    private var settled: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing left to settle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(OvationPalette.ink)
            Text("Every client can be invoiced.")
                .font(.system(size: 13))
                .foregroundStyle(OvationPalette.soft)
            // ONE WORD FOR ONE THING (L118). The settled design file calls it
            // the sidebar, so the screen does too. `rail` survives in the code
            // comments, where no reader of the product meets it.
            Text("This screen is gone from the sidebar. It comes back if a new client arrives "
                 + "without a tax status, or an address stops working.")
                .font(.system(size: 12))
                .foregroundStyle(OvationPalette.quiet)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
    }

    // MARK: the pass itself

    /// AN EAGER STACK, DELIBERATELY. This was a `LazyVStack` until the screen was
    /// rendered: laziness buys nothing over a list bounded by the client count,
    /// which is 31 today and is a roster rather than a feed, and it costs a
    /// branch that only materialises what is on screen. It was swapped while
    /// diagnosing an empty render and kept afterwards on its own merits, not
    /// because it fixed that: the two produced byte identical output, which is
    /// what ruled the laziness out as the cause.
    private var pass: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !presenter.withUnusableAddress.isEmpty {
                    sectionHead(Self.addressSectionTitle,
                                count: presenter.withUnusableAddress.count,
                                said: "Worse than a missing status, so it is first")
                    ForEach(presenter.withUnusableAddress, id: \.id) { client in
                        addressRow(client)
                    }
                }

                if !presenter.needingTaxStatus.isEmpty {
                    sectionHead(Self.taxSectionTitle,
                                count: presenter.needingTaxStatus.count,
                                said: "None of these can be invoiced until it is set")
                    ForEach(presenter.needingTaxStatus, id: \.id) { client in
                        taxRow(client)
                    }
                }

                startedWithFoot
            }
        }
    }

    private func sectionHead(_ title: String, count: Int, said: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .kerning(0.9)
                .foregroundStyle(OvationPalette.faint)
            Text("\(count)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(OvationPalette.soft)
            Spacer()
            Text(said)
                .font(.system(size: 12))
                .foregroundStyle(OvationPalette.quiet)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Divider().overlay(OvationPalette.rule) }
    }

    /// The address is SHOWN and not editable, which is a decision rather than an
    /// omission (PRD 38a, corrected on 2026-09-11). Dan fixes an address in
    /// Downbeat, where client records are kept, so the two can never disagree
    /// about one.
    private func addressRow(_ client: Client) -> some View {
        HStack(spacing: 16) {
            Text(client.name)
                .font(.system(size: 14))
                .foregroundStyle(OvationPalette.ink)
                .lineLimit(1)
            Spacer()
            ForEach(Array(client.contactProblems).sorted(by: { $0.rawValue < $1.rawValue }),
                    id: \.self) { problem in
                Text(problem.sentence)
                    .font(.system(size: 12))
                    .foregroundStyle(OvationPalette.quiet)
            }
            Text(client.email.isEmpty ? "nothing recorded" : client.email)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(OvationPalette.quiet)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(OvationPalette.quiet))
                .lineLimit(1)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Divider().overlay(OvationPalette.ruleSoft) }
    }

    private func taxRow(_ client: Client) -> some View {
        HStack(spacing: 16) {
            Text(client.name)
                .font(.system(size: 14))
                .foregroundStyle(OvationPalette.ink)
                .lineLimit(1)
            Spacer()
            // A VOCABULARY IN CODE IS A PICKER, NEVER A TEXT BOX (L611), and the
            // two answers come from the enum the rest of the app reads rather
            // than from two strings written here.
            HStack(spacing: 6) {
                ForEach([TaxStatus.exempt, TaxStatus.notExempt], id: \.self) { status in
                    Button { record(status, on: client) } label: {
                        chip(status.exportLabel)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Divider().overlay(OvationPalette.ruleSoft) }
    }

    /// NOTHING NATIVE, NOTHING DEFAULT (L607). This was SwiftUI's `.bordered`
    /// button style until the screen was rendered and looked at: the two answers
    /// came out as ghost text with no visible edge, which a view tree test
    /// cannot see because the words were all present. The design record names
    /// this exact trap, that the framework's default control is what ships when
    /// nothing replaces it and it reads as the OS pasted into the product.
    ///
    /// The geometry and the colours are the design file's `.chip` rule, quoted
    /// rather than invented: 12px, 3 by 11 padding, a 4px radius, a one pixel
    /// rule, and the accent filling the one that is chosen.
    /// ONE LOOK, BECAUSE THE OTHER ONE CANNOT HAPPEN HERE. The design file draws
    /// a filled chip for the answer already recorded and this screen carried it
    /// too, until the render was looked at and the state was traced: the section
    /// is built from `needingTaxStatus`, so every client in it holds
    /// `neverRecorded` and neither chip is ever the chosen one. Answering takes
    /// the row out of the list, which is the feedback, along with the count
    /// above it dropping. A branch no fixture can reach is the branch that ships
    /// untested (L29), and `RosterPassTests` states the property that keeps this
    /// removable. The filled treatment belongs on the Clients screen, where a
    /// recorded status is actually displayed.
    private func chip(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 12))
            .foregroundStyle(OvationPalette.soft)
            .padding(.horizontal, 11)
            .padding(.vertical, 3)
            .background(OvationPalette.background)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(OvationPalette.rule, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .fixedSize()
    }

    /// PRD 5a. The number it BEGAN with, which is what makes this read as a one
    /// time job rather than a standing nag.
    private var startedWithFoot: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text("Started with \(presenter.startedWith) of \(presenter.rosterSize)")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(OvationPalette.ink)
            Text("Ovation says the number it began with, so this reads as a one time pass "
                 + "rather than a standing nag. Once it is empty this screen is gone.")
                .font(.system(size: 12))
                .foregroundStyle(OvationPalette.quiet)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    /// NO SILENT GUARD. The throw is already reported by the presenter, which
    /// puts the client back and leaves a sentence on the screen, so there is
    /// nothing for this to swallow.
    private func record(_ status: TaxStatus, on client: Client) {
        try? presenter.answer(client, as: status)
    }
}
