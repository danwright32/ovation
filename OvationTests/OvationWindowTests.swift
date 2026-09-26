import CoreGraphics
import Testing

/// ovation#110. The window's minimum and where a row pairing a client with a shoot
/// changes shape, stated for the window because that is what Dan resizes.
struct OvationWindowTests {

    /// HALF OF DAN'S SCREEN, measured 2026-09-23: 1728 points wide, so a half
    /// screen window is 867, and the minimum must be at or under it.
    @Test("the minimum window fits the half screen Dan works at")
    func theMinimumFitsHalfAScreen() {
        #expect(OvationWindow.minimumWidth == 860)
        #expect(OvationWindow.shootUnderneathBelow == 900)
        #expect(OvationWindow.minimumWidth <= 1728 / 2)
    }

    @Test("at the minimum window the invoice list puts the shoot under the client")
    func atTheMinimumTheShootGoesUnderneath() {
        let list = OvationWindow.minimumWidth - OvationWindow.railWidth

        #expect(OvationWindow.putsShootUnderneath(listWidth: list))
    }

    /// AT THE WIDTH EVERY SCREEN WAS SETTLED AT, 1064, nothing changes: the rule
    /// is for a narrow window and leaves the settled one exactly as it was.
    @Test("at the settled 1064 window the row stays one line")
    func atTheSettledWidthTheRowIsOneLine() {
        #expect(!OvationWindow.putsShootUnderneath(listWidth: 1064 - OvationWindow.railWidth))
    }

    /// THE EDGE IS 900, the narrowest window Dan judged the one line row still
    /// right at, so 900 is one line and a point under it is two.
    @Test("the row switches just below a 900 point window, not at it")
    func theSwitchIsJustBelowTheMeasuredWidth() {
        let atTheEdge = OvationWindow.shootUnderneathBelow - OvationWindow.railWidth

        #expect(!OvationWindow.putsShootUnderneath(listWidth: atTheEdge))
        #expect(OvationWindow.putsShootUnderneath(listWidth: atTheEdge - 1))
    }
}
