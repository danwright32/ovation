// ovation#110. THE WINDOW'S WIDTHS, IN ONE PLACE.
//
// Dan works at half screen (his decision, 2026-09-23). Measured that day on his
// Mac: the visible screen is 1728 points wide and a half screen window 867, so the
// window may be made as narrow as 860 and every screen has to be right there. It
// used to be a literal 900 in `ShellView`, chosen rather than measured, which is
// wider than the half screen he uses.
//
// `scripts/check-design-draws.sh` READS `minimumWidth` FROM THIS FILE and draws
// every design window at it, so the design record and the app cannot come to mean
// two different minimums (L41).
import CoreGraphics

enum OvationWindow {

    /// The narrowest the window may be made: half of Dan's screen.
    static let minimumWidth: CGFloat = 860

    /// Below this window width the invoice list puts the shoot on a line of its
    /// own under the client (Dan, 2026-09-26, ovation#110, PRD 47c).
    ///
    /// HIS, FROM A ROUND DRAWING THE ONE LINE ROW AT 900, 940, 980, 1020 AND 1064:
    /// 900 is the narrowest he judged still right on one line, where the row
    /// shortens every client name and cuts 2 of 16 shoots. It had first been 1020,
    /// the width where a one line row with the SHOOT giving way still held; he
    /// chose instead that the client gives way, which holds far narrower. The
    /// design file switches at the same width, with a container query on the
    /// window. The Clients screen's own rows switch at 1020 in the design file,
    /// for a reason of their own (PRD 47c), and nothing here draws them yet.
    static let shootUnderneathBelow: CGFloat = 900

    /// The rail's width, which every screen's content is laid out beside.
    static let railWidth: CGFloat = 208

    /// Whether a list whose own width is `listWidth` should put the shoot under the
    /// client. The list sits beside the rail, so the window it is in is the list
    /// plus the rail, and the rule is stated for the window because that is what
    /// Dan resizes and what the design record judges.
    static func putsShootUnderneath(listWidth: CGFloat) -> Bool {
        listWidth + railWidth < shootUnderneathBelow
    }
}
