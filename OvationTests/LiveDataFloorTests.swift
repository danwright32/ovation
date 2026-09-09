import Foundation
import Testing

/// Plan 1.9, ovation#58. The floor itself, asserted rather than described.
struct LiveDataFloorTests {

    @Test("every live resolver that exists refuses THIS process, with no arguments passed")
    func everyBuiltResolverRefuses() {
        // The structural half. This suite IS a disposable launch, so a resolver
        // that answers anything at all here would hand a test the real path, and
        // the tests that would use it have not been written yet.
        for entry in LiveDataFloor.built {
            let resolved = entry.resolve?()
            #expect(resolved == nil, "\(entry.name) resolved to \(String(describing: resolved))")
        }
    }

    @Test("the floor is not empty, because a register of nothing checks nothing")
    func theFloorHasMembers() {
        // A list that has quietly emptied would make the test above pass while
        // examining nothing at all (L98).
        #expect(LiveDataFloor.built.count >= 4)
        #expect(!LiveDataFloor.entries.isEmpty)
    }

    @Test("every entry says what it reaches, in words a person can act on")
    func everyEntryExplainsItself() {
        for entry in LiveDataFloor.entries {
            #expect(!entry.name.isEmpty)
            #expect(entry.reaches.count > 20, "\(entry.name) does not say what it reaches")
        }
    }

    @Test("every entry nothing has built yet names the issue that will build it")
    func everyPendingEntryNamesItsIssue() {
        // Plan 1.9 requires the floor to be extended explicitly in each later
        // milestone rather than by whoever notices. An entry with no issue is a
        // gap nobody is waiting on.
        for entry in LiveDataFloor.pending {
            #expect(entry.issue?.hasPrefix("ovation#") == true,
                    "\(entry.name) names no issue")
        }
    }

    @Test("a built entry does not also claim to be waiting on an issue")
    func builtEntriesCarryNoIssue() {
        for entry in LiveDataFloor.built {
            #expect(entry.issue == nil, "\(entry.name) is built and still names \(entry.issue ?? "")")
        }
    }

    @Test("the things that cannot be undone are all in the list")
    func theUnrecoverableOnesAreNamed() {
        // Named individually rather than by count, because a count is satisfied
        // by any eleven entries. These four are the ones whose test write cannot
        // be undone at all.
        let names = Set(LiveDataFloor.entries.map(\.name))
        #expect(names.contains("liveGmailClient"))
        #expect(names.contains("liveConsumedBookingLedger"))
        #expect(names.contains("liveConsumedMessageLedger"))
        #expect(names.contains("liveBookingQueueDirectory"))
    }
}
