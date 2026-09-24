import Foundation
import Testing

/// ovation#42. Where Ovation's own sends go, and who they are from, read from a file on
/// Dan's Mac and never from this repository.
///
/// THE DESTINATION FAILS CLOSED. The first draft of the plan had an environment
/// variable whose ABSENCE meant "send to the real client", which is the inverted
/// default (L42, L72), and a variable does nothing to an app already running. So the
/// send refuses until a destination is written down explicitly, and nothing here has a
/// default that reaches a client.
struct SendingSettingsTests {

    private static func file(_ json: String) throws -> URL {
        let folder = URL.temporaryDirectory
            .appending(path: "ovation-sending-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "sending.json")
        try Data(json.utf8).write(to: url)
        return url
    }

    @Test("a file naming a test address resolves to that address, and says it is redirected")
    func atestAddressResolves() throws {
        let url = try Self.file(#"{"fromName":"Dan Wright","fromEmail":"dan@studio.example","destination":"test","testAddress":"second@elsewhere.example"}"#)

        let settings = try SendingSettings.read(from: url).get()

        #expect(settings.fromName == "Dan Wright")
        #expect(settings.fromEmail == "dan@studio.example")
        #expect(settings.destination == .testAddress("second@elsewhere.example"))
        #expect(settings.destination.recipients(forClient: ["booker@client.example"])
                == ["second@elsewhere.example"])
        #expect(settings.destination.isRedirected)
    }

    @Test("a file naming clients sends to the client's own recipients")
    func clientsResolve() throws {
        let url = try Self.file(#"{"fromName":"Dan Wright","fromEmail":"dan@studio.example","destination":"clients"}"#)

        let settings = try SendingSettings.read(from: url).get()

        #expect(settings.destination == .clients)
        #expect(settings.destination.recipients(forClient: ["a@client.example", "b@client.example"])
                == ["a@client.example", "b@client.example"])
        #expect(!settings.destination.isRedirected)
    }

    /// NO FILE IS A REFUSAL, never "send to the client". That is the whole of failing
    /// closed, and the sentence names the file so the remedy is where to look (L111).
    @Test("no settings file refuses, naming where it should be")
    func nofileRefuses() {
        let url = URL(fileURLWithPath: "/nonexistent/ovation-\(UUID().uuidString)/sending.json")

        let refusal = SendingSettings.read(from: url).failure

        #expect(refusal == .noFile(path: url.path))
        #expect(refusal?.sentence.contains(url.path) == true)
    }

    @Test("each missing field is refused by its own name", arguments: [
        (#"{"fromEmail":"dan@studio.example","destination":"clients"}"#, "fromName"),
        (#"{"fromName":"Dan Wright","destination":"clients"}"#, "fromEmail"),
        (#"{"fromName":"Dan Wright","fromEmail":"dan@studio.example"}"#, "destination"),
        (#"{"fromName":"Dan Wright","fromEmail":"dan@studio.example","destination":"test"}"#, "testAddress"),
    ])
    func amissingFieldIsNamed(json: String, field: String) throws {
        let refusal = SendingSettings.read(from: try Self.file(json)).failure

        #expect(refusal == .missing(field: field))
    }

    /// A BLANK VALUE IS A MISSING ONE: a field present and empty is exactly what a
    /// half-filled template looks like (L67, L138).
    @Test("a field present and blank is refused as missing")
    func ablankFieldIsMissing() throws {
        let url = try Self.file(#"{"fromName":"  ","fromEmail":"dan@studio.example","destination":"clients"}"#)

        #expect(SendingSettings.read(from: url).failure == .missing(field: "fromName"))
    }

    @Test("an address that is not one address is refused, naming the field")
    func anaddressThatIsNotOneIsRefused() throws {
        let url = try Self.file(#"{"fromName":"Dan Wright","fromEmail":"dan@studio.example","destination":"test","testAddress":"second at elsewhere"}"#)

        #expect(SendingSettings.read(from: url).failure == .notAnAddress(field: "testAddress"))
    }

    /// AN UNKNOWN DESTINATION IS REFUSED, never read as either known one. "client"
    /// for "clients" is the typo that would otherwise send a test to a real client.
    @Test("a destination that is neither test nor clients is refused")
    func anunknownDestinationIsRefused() throws {
        let url = try Self.file(#"{"fromName":"Dan Wright","fromEmail":"dan@studio.example","destination":"client"}"#)

        #expect(SendingSettings.read(from: url).failure == .unknownDestination("client"))
    }

    @Test("a file that is not JSON is refused as unreadable, not as missing")
    func afileThatIsNotJSONIsUnreadable() throws {
        let url = try Self.file("destination = test")

        guard case .unreadable = SendingSettings.read(from: url).failure else {
            Issue.record("expected unreadable, got \(String(describing: SendingSettings.read(from: url)))")
            return
        }
    }

    // MARK: where the file lives

    /// THE SAME GATE AS THE GOOGLE CREDENTIALS (ovation#425): a test run and a Debug
    /// build are given NO sending settings path, so neither can send whatever file is
    /// on the Mac, and a real Release run is given one beside the store.
    @Test("there is no live sending settings file inside a test run")
    func nolivefileUnderATestRun() {
        #expect(StoreLocation.liveSendingSettingsFile() == nil)
    }

    @Test("a run that may reach live Google is given the file beside the store, and one that may not is given nothing")
    func therealRunIsGivenTheFile() throws {
        let file = try #require(StoreLocation.liveSendingSettingsFile(mayReachLiveGoogle: true))

        #expect(file.lastPathComponent == "sending.json")
        #expect(file.path.contains("/Ovation/"))
        #expect(!file.path.contains("Ovation-Debug"))
        #expect(StoreLocation.liveSendingSettingsFile(mayReachLiveGoogle: false) == nil)
    }

    /// WHAT THE SHEET SAYS about a redirected send is derived from the destination
    /// itself, so the sheet and the sender cannot disagree about where it is going
    /// (L64, L455).
    @Test("a redirected destination says, in one sentence, that the client will not get it")
    func aredirectSaysSo() {
        let sentence = SendDestination.testAddress("second@elsewhere.example").warning

        #expect(sentence?.contains("second@elsewhere.example") == true)
        #expect(sentence?.contains("not to the client") == true)
        #expect(SendDestination.clients.warning == nil)
    }
}

extension Result {
    /// The failure, or nil. Read by the tests above as a value rather than a switch.
    var failure: Failure? {
        if case .failure(let failure) = self { return failure }
        return nil
    }
}
