import AppKit
import SwiftUI
import Testing
import ViewInspector
@testable import Ovation

/// ovation#40. The first product screen, RASTERISED at the real count so a
/// person can look at it.
///
/// WHY THIS EXISTS AT ALL. L606: a two row fixture and a green suite are the two
/// ways a screen ships unseen, and every other test in this suite reads the view
/// tree rather than looking at it. The app cannot be launched into this screen
/// today either, because nothing imports clients yet, so without this the first
/// product screen Ovation ships would go to merge having been seen by nobody.
///
/// WHAT IT ASSERTS IS DELIBERATELY MODEST. It asserts the view rasterises at the
/// size asked for, which catches a screen that collapses to nothing. It does NOT
/// claim to judge the design: counting ink over a whole surface is answered by
/// whatever the surface paints for itself (L141). The judgement is a person
/// opening the file this writes.
///
/// IT RENDERS THROUGH `NSHostingView`, NOT `ImageRenderer`, and that is a
/// correction made by looking at the output. `ImageRenderer` produced a picture
/// with the rail and the heading drawn and the twenty five rows simply absent:
/// it does not materialise a `ScrollView`, which has no size of its own and gets
/// none from a renderer that proposes nothing. The picture was not evidence that
/// the screen was broken, and it would not have been evidence that it worked
/// either. `NSHostingView` in a real window lays out the way the app does.
///
/// SWAPPING THE LAZY STACK FOR AN EAGER ONE CHANGED NOTHING, measured rather than
/// assumed: the two runs produced byte identical files, which is what ruled the
/// laziness out as the cause.
///
/// WHERE IT WRITES. `TEST_RUNNER_OVATION_RENDER_DIR` when it is set, otherwise a
/// temporary directory. The prefix is not optional: xcodebuild does NOT pass the
/// invoking shell's environment to the test process, and a variable without it
/// arrives as nothing while the run prints a number that looks exactly like an
/// answer.
@MainActor
struct RosterPassRenderTests {

    private static var renderDirectory: URL {
        if let named = ProcessInfo.processInfo.environment["OVATION_RENDER_DIR"] {
            return URL(fileURLWithPath: named, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("ovation-renders", isDirectory: true)
    }

    /// 31 clients, 25 of them with no sales tax status, which is the roster
    /// measured from the live Downbeat export on 2026-09-11.
    private static func theRealRoster() -> [Client] {
        let names = [
            "Ashgrove Chamber Players", "Bellweather Dance Collective",
            "Brackenridge Youth Orchestra", "Calder Street Theatre", "Cormorant Bay Singers",
            "Drayton Wind Ensemble", "Eastvale Opera Workshop", "Fenwick Early Music Society",
            "Gallowmere Brass Band", "Harborlight Ballet", "Inglenook Jazz Collective",
            "Juniper Row Playhouse", "Kestrel Lane Quartet", "Larkspur Community Chorus",
            "Marisol Okonkwo-Reyes", "Marrowbone Percussion Group", "Nettlefield Baroque Consort",
            "Orchard Hill Symphonia", "Pennywhistle Folk Circle", "Priya Raghunathan",
            "Quillon Contemporary Dance", "Redbourne Light Opera", "Saltmarsh String Orchestra",
            "Thistledown Puppet Theatre", "Tobias Fenn", "Underhill Gospel Choir",
            "Vesper Lane Chamber Society", "Westfield Choral Society", "Wrenfield Academy of Dance",
            "Yarrow Street Collective", "Zephyr Hall Concerts",
        ]
        // The six that already carry one, so the pass is 25, as measured. The
        // names are the design file's invented fixture, never a real client
        // (docs/PRIVACY-FLOOR.md).
        let answered: Set<String> = [
            "Calder Street Theatre", "Harborlight Ballet", "Larkspur Community Chorus",
            "Underhill Gospel Choir", "Westfield Choral Society", "Zephyr Hall Concerts",
        ]
        return names.map { name in
            let c = Client(name: name,
                           taxStatus: answered.contains(name) ? .notExempt : .neverRecorded)
            c.email = "office@example.example"
            return c
        }
    }

    @Test("the first product screen rasterises at the real count")
    func itRasterisesAtTheRealCount() throws {
        let roster = RosterPresenter(clients: Self.theRealRoster(), save: {})
        #expect(roster.startedWith == 25)
        #expect(roster.rosterSize == 31)

        let problems = ProblemsStore(journal: InMemoryProblemsJournal())
        _ = problems.raise(kind: .backupFailed, subject: "b",
                           sentence: "No backup folder has been chosen yet.", now: Date())

        let view = ShellView(
            shell: ShellPresenter(selected: .roster, rosterHasWork: { true }),
            roster: roster,
            problems: problems)

        let size = NSSize(width: 1064, height: 980)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()

        let bitmap = try #require(
            host.bitmapImageRepForCachingDisplay(in: host.bounds),
            "the shell produced no bitmap at all")
        host.cacheDisplay(in: host.bounds, to: bitmap)

        #expect(bitmap.size.width == size.width)

        try? FileManager.default.createDirectory(
            at: Self.renderDirectory, withIntermediateDirectories: true)
        if let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: Self.renderDirectory.appendingPathComponent("roster-pass.png"))
        }
    }
}
