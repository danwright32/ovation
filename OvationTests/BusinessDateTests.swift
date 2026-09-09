import Foundation
import Testing

/// Plan 1.6, ovation#55. A money bearing date is stamped with the business day
/// it belongs to at the moment it is written, and that answer never moves again.
@Suite(.serialized)
struct BusinessDateTests {

    // MARK: stamping

    @Test("stamping settles which business day an instant belongs to")
    func stampingSettlesTheDay() {
        // 2026-12-31 23:30 America/New_York, which is 2027-01-01 04:30 UTC.
        let stamped = BusinessDate.stamping(utc(2027, 1, 1, 4, 30))

        #expect(stamped.dayKey == "2026-12-31")
        #expect(stamped.year == 2026)
        #expect(stamped.instant == utc(2027, 1, 1, 4, 30))
    }

    @Test("the instant is kept as well as the key, because they answer different questions")
    func bothHalvesAreKept() {
        // The instant is the fact: when it happened. The key is the settled
        // answer: which business day that was. An export that had only the
        // instant would have to do timezone arithmetic at read time, and one
        // that had only the key could never say when in the day it happened.
        let instant = utc(2026, 7, 4, 15, 0)
        let stamped = BusinessDate.stamping(instant)

        #expect(stamped.instant == instant)
        #expect(stamped.dayKey == BusinessCalendar.dayKey(for: instant))
    }

    @Test("stamping does not depend on where the machine is")
    func stampingIgnoresTheHostZone() {
        withHostTimeZone("Pacific/Auckland") {
            #expect(BusinessDate.stamping(utc(2027, 1, 1, 4, 30)).dayKey == "2026-12-31")
        }
    }

    // MARK: the stamp is not re-derived on the way back

    @Test("a row read back keeps the key it was stored with, even when re-deriving would disagree")
    func theStoredKeyWins() {
        // This is the whole point. A key written under one rule must not silently
        // change when the rule, the calendar or the machine changes: re-running
        // last January's export has to produce last January's numbers (L37).
        let row = BusinessDate(storedInstant: utc(2027, 1, 1, 4, 30),
                               storedDayKey: "2027-01-01")

        #expect(row.dayKey == "2027-01-01")
        #expect(row.year == 2027)
    }

    @Test("but a row whose key and instant disagree says so, rather than hiding it")
    func disagreementIsVisible() {
        // Keeping the stored key is right. Saying nothing about a row where the
        // two halves disagree is not: it is either a rule change worth knowing
        // about or a corrupt row, and the surface that reports it is the Problems
        // store (ovation#59).
        let disagreeing = BusinessDate(storedInstant: utc(2027, 1, 1, 4, 30),
                                       storedDayKey: "2027-01-01")
        #expect(!disagreeing.agreesWithItsInstant)

        let stamped = BusinessDate.stamping(utc(2027, 1, 1, 4, 30))
        #expect(stamped.agreesWithItsInstant)
    }

    @Test("a stored key that is not a day key at all has no year, and the row still loads")
    func aMalformedKeyIsReportedRatherThanLosingTheRow() {
        let broken = BusinessDate(storedInstant: utc(2026, 7, 4, 15, 0), storedDayKey: "whenever")

        #expect(broken.year == nil)
        #expect(!broken.agreesWithItsInstant)
        #expect(broken.instant == utc(2026, 7, 4, 15, 0))
    }

    // MARK: storage

    @Test("encoding and decoding preserves both halves exactly, disagreement included")
    func codingDoesNotReDerive() throws {
        // The regression this guards: a decoder that recomputed the key from the
        // instant would make every one of the assertions above true in memory and
        // false the moment a row came back from the store, which is the only place
        // it matters.
        let disagreeing = BusinessDate(storedInstant: utc(2027, 1, 1, 4, 30),
                                       storedDayKey: "2027-01-01")

        let data = try JSONEncoder().encode(disagreeing)
        let decoded = try JSONDecoder().decode(BusinessDate.self, from: data)

        #expect(decoded.dayKey == "2027-01-01")
        #expect(decoded.instant == disagreeing.instant)
        #expect(decoded == disagreeing)
    }

    @Test("the encoded shape is the instant and the key, under names a store can read")
    func theEncodedShapeIsStated() throws {
        let data = try JSONEncoder().encode(BusinessDate.stamping(utc(2026, 7, 4, 15, 0)))
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object.keys.sorted() == ["dayKey", "instant"])
        #expect(object["dayKey"] as? String == "2026-07-04")
    }

    // MARK: ordering and grouping

    @Test("dates order by their instant, which is the fact")
    func orderingIsByInstant() {
        let earlier = BusinessDate.stamping(utc(2026, 7, 4, 15, 0))
        let later = BusinessDate.stamping(utc(2026, 7, 4, 16, 0))

        #expect(earlier < later)
        #expect(earlier.dayKey == later.dayKey)
    }

    @Test("day keys sort as text in the same order as the days they name")
    func keysSortAsText() {
        // ISO ordering is why the export can group and sort on the stamped key
        // without parsing it back into a date.
        let keys = [utc(2027, 1, 1, 4, 30), utc(2026, 2, 1, 4, 30), utc(2026, 7, 4, 15, 0)]
            .map { BusinessDate.stamping($0).dayKey }

        #expect(keys.sorted() == ["2026-01-31", "2026-07-04", "2026-12-31"])
    }

    // MARK: fixtures

    private func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: components)!
    }

    private func withHostTimeZone(_ identifier: String, _ body: () -> Void) {
        let previous = getenv("TZ").map { String(cString: $0) }
        setenv("TZ", identifier, 1)
        NSTimeZone.resetSystemTimeZone()
        defer {
            if let previous { setenv("TZ", previous, 1) } else { unsetenv("TZ") }
            NSTimeZone.resetSystemTimeZone()
        }
        let requested = TimeZone(identifier: identifier)
        #expect(requested != nil)
        #expect(TimeZone.current.secondsFromGMT() == requested?.secondsFromGMT())
        #expect(TimeZone.current.secondsFromGMT() != BusinessCalendar.timeZone.secondsFromGMT())
        body()
    }
}
