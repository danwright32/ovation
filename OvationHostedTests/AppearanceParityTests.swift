// ovation#474, PRD 43. Every screen draws the same whatever the Mac is set to.
//
// THE DECISION IS RECORDED AND WAS ENFORCED BY NOTHING. `OvationPalette`'s header
// says Ovation does not follow the system appearance and has no dark half, which
// Dan accepted in exchange for not carrying a second palette and a second set of
// contrast guards through every screen. That held only for as long as nothing on
// a screen painted its OWN background, and a native control does: the `DatePicker`
// for the shoot's times rendered black with white text in dark while the page
// around it stayed cream, on the Mac Dan actually uses (L231, L607).
//
// WHY IT WAS NOT CAUGHT. Two of the four shot suites already carried this
// assertion, and both are OPT IN on a shot directory CI does not set, so each
// printed "nothing was captured" and passed. A guard that reports success when it
// found nothing to watch is indistinguishable from one that saw everything pass
// (L98). The comparison needs no directory, so it does not live behind one any
// more: filing pictures is opt in, and this is not.
//
// IT IS ONE SUITE RATHER THAN A LINE IN EACH, so a screen added with a picture
// cannot be the one that quietly lacks it (L613). Its residual is stated rather
// than left to be discovered: a screen with no entry here is not covered, and the
// list below is maintained by hand, so it carries the same weakness as any hand
// written registry (L96).
import AppKit
import SwiftData
import SwiftUI
import Testing
@testable import Ovation

@MainActor
struct AppearanceParityTests {

    /// HELD FOR THE WHOLE CASE, not made inside the builder: releasing it deletes
    /// its folder, and the window reads the footer from it while it draws.
    private let throwaway: ThrowawayDefaults

    init() throws {
        throwaway = try ThrowawayDefaults()
    }

    private static let noon = Date(timeIntervalSince1970: 1_794_531_600)
    private static let today = BusinessDate.stamping(noon)

    /// The screens this covers.
    ///
    /// THE SETTINGS WINDOW IS TWO OF THEM (ovation#475). Measured 2026-09-21, its
    /// invoices pane drew its headings in a near black on a black page when the
    /// Mac was dark: the window is made by macOS, so its background and every
    /// standard colour on it came from the WINDOW's appearance, which the SwiftUI
    /// environment override did not reach. It is captured here both as the pane
    /// alone and as the whole window with its tabs, because the tab control is
    /// chrome the pane does not draw.
    ///
    /// THE BACKUPS TAB IS NOT CAPTURED ON ITS OWN. The appearance is pinned on the
    /// window, which both tabs share, so the whole window case covers what paints
    /// it; what that case cannot see is a colour the backups pane sets for itself.
    enum Screen: String, CaseIterable {
        case theInvoice
        case theInvoiceList
        case theInvoiceSettings
        case theSettingsWindow
    }

    @Test("every screen draws the same in dark as in light", arguments: Screen.allCases)
    func everyscreenDrawsTheSame(screen: Screen) throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ovation-parity-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let light = directory.appending(path: "light.png")
        let dark = directory.appending(path: "dark.png")
        let size = CGSize(width: 856, height: 560)
        try capture(screen, size: size, scheme: .light, to: light)
        try capture(screen, size: size, scheme: .dark, to: dark)

        let lightBytes = try Data(contentsOf: light)
        let darkBytes = try Data(contentsOf: dark)

        #expect(lightBytes == darkBytes,
                "\(screen.rawValue) draws differently in dark, so something on it takes a colour from the system rather than from OvationPalette, whose header records that there is no dark half")
        // THE PICTURE IS OF SOMETHING. Two identical blank captures would satisfy
        // the line above for ever, which is the one way this could pass while
        // measuring nothing (L98).
        #expect(lightBytes.count > 5_000, "\(screen.rawValue) captured \(lightBytes.count) bytes, which is not a screen")
    }

    @ViewBuilder
    private func view(for screen: Screen) throws -> some View {
        switch screen {
        case .theInvoice:
            InvoiceScreenView(presenter: try Self.invoice(), close: {}, setTime: { _, _, _ in })
        case .theInvoiceList:
            InvoiceListView(presenter: try Self.list(), heldMoney: "500.00",
                            selected: .constant(nil), open: { _ in })
        case .theInvoiceSettings:
            InvoiceSettingsView(footer: .constant(.fixed))
        case .theSettingsWindow:
            settings()
        }
    }

    private func capture(_ screen: Screen, size: CGSize, scheme: ColorScheme, to url: URL) throws {
        try OffscreenShot.capture(try view(for: screen), size: size, scheme: scheme, to: url)
    }

    /// A DRAFT WITH THE TIME FIELDS ON IT, because the native control is the whole
    /// reason this suite exists and a fixture without one would pass whatever
    /// happened (L159).
    private static func invoice() throws -> InvoiceScreenPresenter {
        let context = ModelContext(try OvationSchema.container(inMemory: true))
        let client = Client(name: "Cedar Hill Youth Orchestra", taxStatus: .notExempt)
        context.insert(client)
        let invoice = Invoice(client: client, kind: .photography, invoiceDate: today,
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity)
        invoice.dueDate = .stamping(noon.addingTimeInterval(14 * 86_400))
        context.insert(invoice)
        let shoot = Shoot(name: "Autumn Evensong", when: .dayOnly(today), venue: "St Anne's")
        shoot.shotFrom = ClockTime("19:00")
        shoot.shotUntil = ClockTime("20:30")
        invoice.add(shoot)
        invoice.add(LineItem.hourly(hours: Hours(whole: 1), at: Money(dollars: 250),
                                    describedAs: "Photography", for: shoot))
        return InvoiceScreenPresenter(invoice: invoice, footer: .fixed, today: today)
    }

    /// THE WINDOW AS SETTINGS BUILDS IT, over a throwaway defaults suite, because
    /// the invoices pane WRITES and a capture must not reach Dan's real footer
    /// (L201). A disposable launch, so the backups half never looks for a folder.
    private func settings() -> SettingsView {
        SettingsView(
            backups: BackupSettingsPresenter(
                setting: BackupFolderSetting(defaults: throwaway.defaults,
                                             isDisposableLaunch: { true }),
                dataDirectory: URL(fileURLWithPath: NSTemporaryDirectory()),
                problems: ProblemsStore(journal: InMemoryProblemsJournal()),
                now: Date.init,
                askForAFolder: { nil }),
            invoiceFooter: InvoiceFooterSetting(defaults: throwaway.defaults))
    }

    private static func list() throws -> InvoiceListPresenter {
        let context = ModelContext(try OvationSchema.container(inMemory: true))
        let client = Client(name: "Cedar Hill Youth Orchestra", taxStatus: .notExempt)
        context.insert(client)
        let invoice = Invoice(client: client, kind: .photography, invoiceDate: today,
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity)
        context.insert(invoice)
        let shoot = Shoot(name: "Autumn Evensong", when: .dayOnly(today), venue: "St Anne's")
        invoice.add(shoot)
        let line = LineItem.hourly(hours: Hours(whole: 1), at: Money(dollars: 250),
                                   describedAs: "Photography", for: shoot)
        line.hours = nil
        invoice.add(line)
        return InvoiceListPresenter(invoices: [invoice], heldMoney: [:], today: today)
    }
}
