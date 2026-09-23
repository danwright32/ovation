// The colours the first screens draw with, lifted from the settled design files
// rather than chosen here.
//
// THIS IS NOT A TOKEN SYSTEM AND MUST NOT GROW INTO ONE BY ACCIDENT. Whether
// Ovation shares the siblings' design token machinery or keeps its own is
// ovation#94, still open. This is the smallest thing that lets the first screen
// draw the agreed colours, with every value quoted from
// `docs/design/shell/palette.css`, so that when #94 is settled there is one
// place to replace rather than a colour literal at every call site (L585).
//
// LIGHT MODE ONLY, DELIBERATELY (PRD 43). Ovation does not follow the system
// appearance, and the absence of a dark half here is a recorded decision rather
// than an oversight: Dan's Mac is set to dark and he accepted a bright window in
// exchange for not carrying a second palette and a second set of contrast guards
// through every screen. Reversing it is a design round plus a second token set.
import SwiftUI

enum OvationPalette {
    // The page and its rules.
    static let background = Color(hex: 0xFBF4EF)
    static let chrome = Color(hex: 0xEFE8E3)
    static let rule = Color(hex: 0xE0D0C4)
    static let ruleSoft = Color(hex: 0xEEE2D8)
    /// The tint a selected row carries, `--selbg` in the design record. A selected
    /// row is marked by this ALONE and never a left bar (PRD 47), which is both
    /// the macOS convention and a practical necessity once the sidebar is dark.
    static let selection = Color(hex: 0xE4DCD6)
    /// A surface you are working on, `--sunk` in `docs/design/shell/palette.css`.
    /// The invoice's row being filled in and the design record's own fields are
    /// drawn on it. ovation#457.
    static let sunk = Color(hex: 0xF1EAE5)
    /// The accent, `--accent` in the same file, which the design puts on the one
    /// control a panel is for.
    ///
    /// IT IS THE SAME VALUE AS `rail` AND IT IS NOT THE SAME TOKEN. The rail is a
    /// dark SURFACE and this is an accent drawn ON the page, and they are equal
    /// today by the design's own choice rather than by anything that must stay
    /// true. A call site that wants an accent and reaches for `rail` is asserting
    /// a role the name denies, and the day the two diverge nothing would find it
    /// (L176, L213).
    static let accent = Color(hex: 0x3B2B21)

    // Ink, in the four weights the design uses.
    static let ink = Color(hex: 0x1F1812)
    static let soft = Color(hex: 0x5F4D41)
    static let quiet = Color(hex: 0x766254)
    static let faint = Color(hex: 0x6E5F50)

    // The espresso rail (PRD 44).
    static let rail = Color(hex: 0x3B2B21)
    static let railItem = Color(hex: 0xBCB7B4)
    static let railOnBackground = Color(hex: 0x5A4D45)
    static let railOnText = Color(hex: 0xF3F2F2)
    static let railCardBackground = Color(hex: 0x4D3E35)
    static let railCardBorder = Color(hex: 0x62554D)
    static let railCardHeading = Color(hex: 0xD4D0CE)
    static let railCardLine = Color(hex: 0xDCD9D7)
    static let railStatusBorder = Color(hex: 0x5A4D45)
    static let railFault = Color(hex: 0xF3F2F2)
    static let railDim = Color(hex: 0xC4BFBC)
}

extension Color {
    /// The design files are written in hex, so the values above are quoted
    /// rather than converted, which is one fewer place for one to be mistyped.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1)
    }
}

// MARK: the appearance the palette assumes

extension View {

    /// PRD 43, ovation#474. Ovation does not follow the system appearance, and
    /// this is what makes that true rather than merely recorded.
    ///
    /// EVERY COLOUR IN THIS PRODUCT COMES FROM `OvationPalette`, which has no dark
    /// half by decision, so a screen was the same in both appearances for as long
    /// as nothing on it painted its OWN background. A native control does: the
    /// `DatePicker` added for the shoot's times renders black with white text in
    /// dark while the page around it stays cream, and on the Mac Dan actually uses
    /// that is the one control he has to type into (L231, L607).
    ///
    /// SO IT IS SET, NOT ASSUMED, and it is set on the SCREEN rather than on the
    /// control, because the next native control will be somewhere else and the
    /// rule is about the surface. `AppearanceParityTests` renders every screen
    /// that has a picture in both appearances and refuses a difference.
    func ovationAppearance() -> some View {
        environment(\.colorScheme, .light)
    }
}
