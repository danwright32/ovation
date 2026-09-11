// ovation#40, PRD 44a and 44. The window: the espresso rail, and whatever screen
// you are standing on.
//
// THE RAIL IS FULL HEIGHT AND CARRIES THE COLOUR (PRD 44). In the design file
// the traffic lights are drawn on it by hand; here the system draws them, which
// is one of the three web idioms the design record says must be translated
// rather than copied.
//
// THE CARD SAYS WHAT IS TRUE ON DAY ONE. PRD 46a's five counts are counts of
// INVOICES, and Ovation holds none, so the card says `Nothing waiting` rather
// than borrowing the invoice list's fixture numbers. A number in this card means
// this many things need you (PRD 46b), and drawing four that nothing can produce
// would break that promise on the first screen that ever states it.
//
// MONEY HELD IS NOT DRAWN AT ALL YET, and that is the zero rule rather than an
// omission: PRD 46b makes it a quantity, and a quantity of nothing is not drawn.
import SwiftUI

struct ShellView: View {
    @Bindable var shell: ShellPresenter
    @Bindable var roster: RosterPresenter
    /// WHERE A LAUNCH NOTICE LANDS ONCE THE SHELL OWNS THE WINDOW. `RootView` is
    /// the one surface every launch time condition reaches Dan through
    /// (ovation#59), and this view REPLACES it, so without the status block at
    /// the foot of the rail a foreign store, a failed backup or a stale export
    /// would be raised, recorded, and seen by nobody (L242, L98).
    ///
    /// NOT OPTIONAL AND WITH NO DEFAULT, deliberately. A default would let a
    /// future call site forget the wiring and still compile, which is the whole
    /// shape of this failure (L168).
    @Bindable var problems: ProblemsStore

    /// What a destination with no screen behind it says about itself. A constant
    /// because a test counts them, and because the same words appear once per
    /// unbuilt entry and must not drift between them.
    static let notBuiltMark = "not built yet"

    var body: some View {
        HStack(spacing: 0) {
            rail
            content
        }
        .frame(minWidth: 900, minHeight: 620, alignment: .topLeading)
    }

    // MARK: the rail

    private var rail: some View {
        VStack(alignment: .leading, spacing: 1) {
            card
            ForEach(shell.destinations, id: \.self) { destination in
                railItem(destination)
            }
            Spacer(minLength: 14)
            status
        }
        .padding(.horizontal, 9)
        .padding(.top, 34)
        .padding(.bottom, 12)
        .frame(width: 208, alignment: .topLeading)
        .background(OvationPalette.rail)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Needs you")
                .font(.system(size: 10, weight: .bold))
                .textCase(.uppercase)
                .kerning(1.3)
                .foregroundStyle(OvationPalette.railCardHeading)
            Text("Nothing waiting")
                .font(.system(size: 12.5))
                .foregroundStyle(OvationPalette.railCardLine)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(OvationPalette.railCardBackground)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(OvationPalette.railCardBorder))
        .padding(.horizontal, 3)
        .padding(.bottom, 10)
    }

    private func railItem(_ destination: Destination) -> some View {
        let isHere = destination == shell.selected
        return Button {
            shell.go(to: destination)
        } label: {
            HStack(spacing: 8) {
                Text(destination.title)
                    .font(.system(size: 13))
                    .foregroundStyle(isHere ? OvationPalette.railOnText : OvationPalette.railItem)
                Spacer()
                if !destination.isBuilt {
                    // PRESENT AND SAYING SO (PRD 44a). A destination that is
                    // present and silent is a dead control nobody can ask about,
                    // and one that is simply absent teaches nothing (L49, L109).
                    Text(Self.notBuiltMark)
                        .font(.system(size: 10.5))
                        .foregroundStyle(OvationPalette.railDim)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHere ? OvationPalette.railOnBackground : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .disabled(!destination.isBuilt)
    }

    // MARK: what is wrong, at the foot of the rail

    /// THE ZERO RULE, for the fifth surface it now governs. A rail with nothing
    /// wrong says nothing at all, rather than saying nothing is wrong in the one
    /// place reserved for things that are.
    @ViewBuilder
    private var status: some View {
        let open = problems.open
        if let first = open.first {
            VStack(alignment: .leading, spacing: 5) {
                Text(first.sentence)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(OvationPalette.railFault)
                    .fixedSize(horizontal: false, vertical: true)
                if let others = Self.othersSentence(open.count - 1) {
                    Text(others)
                        .font(.system(size: 11.5))
                        .foregroundStyle(OvationPalette.railDim)
                }
                Text("Ovation only looks while it is open.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(OvationPalette.railDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .overlay(alignment: .top) { Divider().overlay(OvationPalette.railStatusBorder) }
            .padding(.horizontal, 3)
        }
    }

    /// What the rail says about the ones behind the first. Nothing at all when
    /// there are none, because `0 other problems` is noise. Singular and plural
    /// are separate, because `1 other problems` is the kind of sentence that
    /// makes a person stop trusting the rest of the screen.
    static func othersSentence(_ others: Int) -> String? {
        switch others {
        case ..<1: return nil
        case 1: return "1 other problem"
        default: return "\(others) other problems"
        }
    }

    // MARK: what you are standing on

    @ViewBuilder
    private var content: some View {
        switch shell.selected {
        case .roster:
            RosterPassView(presenter: roster)
        case .invoices, .expenses, .clients:
            // Reachable only from a test today, because `go(to:)` refuses an
            // unbuilt destination. It is drawn rather than left blank so that
            // the state has a sentence if it is ever reached (L10).
            VStack(alignment: .leading, spacing: 6) {
                Text(shell.selected.title)
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .foregroundStyle(OvationPalette.ink)
                Text("This screen has not been built yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(OvationPalette.soft)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
            .background(OvationPalette.background)
        }
    }
}
