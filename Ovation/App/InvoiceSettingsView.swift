// ovation#319, PRD 9. The three sentences at the foot of every invoice, where Dan
// can change them.
//
// IT EDITS THE TYPE THE PAGE IS BUILT FROM, `InvoiceFooter`, rather than a second
// struct that has to be copied into it (L317).
//
// TWO TYPES ON PURPOSE. `InvoiceSettingsView` only draws and edits what it is
// handed, so it can be rendered at any state a picture is wanted of, including the
// all empty one no stored setting would produce. `InvoiceSettingsPane` is the one
// wired into Settings: it owns the stored value and saves what changes.
//
// WHAT IT SAYS WHEN A REQUIRED LINE IS EMPTY WAS FOUND BY LOOKING AT IT. The first
// rendering drew three identical empty boxes, two of which silently stop every
// invoice in the app from going out, and nothing on the pane said so: a surface
// that never got a warning cannot be told from one with nothing to warn about
// (L678, L109). The box that is OPTIONAL was the only one whose hint mentioned
// being empty, which is exactly backwards.
import SwiftUI

struct InvoiceSettingsView: View {

    @Binding var footer: InvoiceFooter

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // THE ONE THING THE READER CANNOT KNOW, said once, at the top
                // (L604, L605). Where this text ends up is a fact about invoices
                // rather than an explanation of the boxes, and repeating it on each
                // field would be three copies of one sentence.
                Text("These appear at the foot of every invoice you send.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                field("Payment instructions",
                      help: "How a client pays you. Bank details belong here.",
                      text: $footer.payment,
                      blocking: footer.refusals.contains(.paymentInstructionsNotSet))
                Divider()
                field("Note to the client",
                      help: "Left off the invoice when empty.",
                      text: $footer.note,
                      blocking: false)
                Divider()
                field("Contact details",
                      help: "However you want clients to reach you.",
                      text: $footer.contact,
                      blocking: footer.refusals.contains(.contactDetailsNotSet))
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// One labelled block.
    ///
    /// A TEXT EDITOR, NOT A TEXT FIELD, and that is the point: payment instructions
    /// are bank details over several lines, and a control that could hold only one
    /// line would decide the copy (L607, L568).
    ///
    /// `blocking` IS DERIVED FROM THE FOOTER'S OWN REFUSALS, never from a second
    /// emptiness test written here, so this pane and the control that refuses the
    /// send cannot come to disagree about what empty means (L70).
    private func field(_ title: String, help: String,
                       text: Binding<String>, blocking: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(help).font(.caption).foregroundStyle(.secondary)
            TextEditor(text: text)
                .font(.body)
                .frame(minHeight: 58)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .textBackgroundColor)))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(blocking ? Color.orange : Color(nsColor: .separatorColor)))
                .scrollContentBackground(.hidden)
            if blocking {
                // SAYS WHAT IS STOPPED, not that the box is empty, which the reader
                // can already see (L604). The consequence is the fact they do not
                // have. The colour is not the only carrier of it: the sentence says
                // the same thing (L149).
                Label("No invoice can be sent while this is empty.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}

/// The pane Settings actually shows: the stored footer, with every edit saved.
///
/// IT SEEDS ITS STATE ONCE AND SAVES IN THE BINDING'S SETTER, never from an effect
/// that runs when it appears. A control that seeds itself from stored state and
/// then writes that state from a mount effect overwrites the person's change every
/// time its container is rebuilt (L646). Appearing reads; typing writes.
///
/// THE SAVE IS IN THE BINDING RATHER THAN IN AN `onChange` BESIDE IT, and that is
/// what makes it provable. An `onChange` is a second thing the view has to
/// remember to carry, reachable only by driving SwiftUI, so the one piece of this
/// feature Dan would notice failing was the one piece no test could reach (L3).
/// Written this way the storing IS the editing: `footerBinding` is an ordinary
/// value a test can write through, and there is no path that edits without saving.
struct InvoiceSettingsPane: View {

    private let setting: InvoiceFooterSetting
    @State private var footer: InvoiceFooter

    init(setting: InvoiceFooterSetting) {
        self.setting = setting
        _footer = State(initialValue: setting.footer)
    }

    /// What the boxes write through. Internal so its suite can drive it exactly as
    /// typing does, rather than reaching into the view hierarchy to find a control.
    var footerBinding: Binding<InvoiceFooter> {
        Binding(get: { footer },
                set: { edited in
                    footer = edited
                    setting.save(edited)
                })
    }

    var body: some View {
        InvoiceSettingsView(footer: footerBinding)
    }
}
