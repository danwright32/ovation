import Foundation
import SwiftData
import Testing

/// ovation#185, PRD 14h. What makes Ovation apply held money BY ITSELF: a pass run
/// once when the store opens and again after every committed write, whoever made
/// it, and a failed pass said rather than swallowed.
@MainActor
struct HeldMoneyPassTests {

    private static let noon = Date(timeIntervalSince1970: 1_790_438_400)
    private static let today = BusinessDate.stamping(noon)

    private static func problems() -> ProblemsStore {
        ProblemsStore(journal: InMemoryProblemsJournal())
    }

    /// A client holding `holding` with one sent invoice owing 300.
    private static func store(holding: Money) throws -> (ModelContainer, invoice: UUID) {
        let container = try OvationSchema.container(inMemory: true)
        let context = ModelContext(container)
        let client = Client(name: "Cedar Hill Youth Orchestra", taxStatus: .exempt)
        context.insert(client)
        let invoice = Invoice(client: client, kind: .photography, invoiceDate: today,
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity,
                              createdOn: today)
        context.insert(invoice)
        invoice.add(LineItem.flat(Money(dollars: 300), describedAs: "Photography"))
        invoice.sentStatus = .sent(route: .ovationSentIt, at: noon)
        if holding > .zero {
            context.insert(Payment(client: client, amount: holding, method: .zelle,
                                   receivedOn: today))
        }
        try context.save()
        return (container, invoice.id)
    }

    private static func paid(_ container: ModelContainer, _ id: UUID) throws -> Money {
        try #require(try ModelContext(container).fetch(FetchDescriptor<Invoice>())
            .first { $0.id == id }).amountPaid
    }

    /// Waits on the condition itself, bounded, so a pass that never comes fails
    /// with its name rather than hanging the run (L290, L110).
    private static func eventually(_ condition: () throws -> Bool) async throws -> Bool {
        for _ in 0..<300 {
            if try condition() { return true }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        return try condition()
    }

    @Test("a pass over a store holding money for one open invoice puts it there")
    func apassPlacesIt() async throws {
        let (container, invoice) = try Self.store(holding: Money(dollars: 100))
        let pass = HeldMoneyPass(over: container, problems: Self.problems(), now: { Self.noon })

        await pass.pass()

        #expect(try Self.paid(container, invoice) == Money(dollars: 100))
    }

    /// THE REASON IT LISTENS RATHER THAN BEING CALLED: a write from anywhere, here
    /// a payment inserted by a context the pass knows nothing about, is followed by
    /// a pass without that writer having to ask for one (L621).
    @Test("a write made anywhere afterwards is followed by a pass")
    func awriteIsFollowedByAPass() async throws {
        let (container, invoice) = try Self.store(holding: .zero)
        let pass = HeldMoneyPass(over: container, problems: Self.problems(), now: { Self.noon })
        await pass.pass()
        #expect(try Self.paid(container, invoice) == .zero, "nothing is held yet, so nothing moved")

        let elsewhere = ModelContext(container)
        let client = try #require(try elsewhere.fetch(FetchDescriptor<Client>()).first)
        elsewhere.insert(Payment(client: client, amount: Money(dollars: 120), method: .zelle,
                                 receivedOn: Self.today))
        try elsewhere.save()

        #expect(try await Self.eventually { try Self.paid(container, invoice) == Money(dollars: 120) })
        withExtendedLifetime(pass) {}
    }

    @Test("a pass that fails is said as a problem, and the next pass that works resolves it")
    func afailedPassIsSaid() async throws {
        struct Refused: Error, CustomStringConvertible {
            var description: String { "the store refused the write" }
        }
        final class Plan: @unchecked Sendable { var fails = true }
        let plan = Plan()
        let problems = Self.problems()
        let pass = HeldMoneyPass(place: { _ in if plan.fails { throw Refused() } },
                                 problems: problems, now: { Self.noon })

        await pass.pass()

        let said = try #require(problems.open.first { $0.kind == .heldMoneyNotPlaced })
        #expect(said.sentence.contains("the store refused the write"),
                "the problem names what went wrong rather than that something did")

        plan.fails = false
        await pass.pass()

        #expect(!problems.open.contains { $0.kind == .heldMoneyNotPlaced })
    }
}
