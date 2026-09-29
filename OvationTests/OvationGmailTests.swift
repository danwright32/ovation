import BackstageGoogle
import Foundation
import Testing

/// ovation#425 and ovation#426. Ovation's one Gmail call site, and the scopes it
/// is allowed to ask Google for.
///
/// WHY IT IS TESTED IN OVATION AND NOT ONLY IN BACKSTAGE. backstage#40's
/// complaint is that the no default scopes rule is only ever proved by a fixture
/// inside backstage. A shared definition is shared only while both sides agree
/// what it means, and two same named things either side of a boundary implement
/// different rules for ever (L263). These assert the contract OVATION depends on,
/// inside Ovation's own process, against the pinned binary.
///
/// NEITHER CREDENTIALS NOR A NETWORK. Constructing the manager computes two file
/// URLs and asks nothing of the disk, so every case here runs with nothing
/// provisioned.
@MainActor
struct OvationGmailTests {

    // MARK: the scopes Ovation may ask for (ovation#426)

    /// AN ALLOW LIST, NEVER A DENY LIST OF GOOGLE'S RESTRICTED SCOPES. A deny list
    /// has to mirror Google's policy by hand, permanently exempts anything they
    /// reclassify, and is named for the question it appears to answer (L41, L257,
    /// L42, L72).
    @Test("the approved list is exactly gmail.send, and it is the whole list")
    func theapprovedListIsExactlySend() {
        #expect(OvationGmail.approvedScopes == ["https://www.googleapis.com/auth/gmail.send"])
    }

    @Test("a scope nobody approved is refused by name")
    func anunapprovedScopeIsRefused() {
        // gmail.readonly is the one Ovation will actually want next (ovation#41's
        // probe and ovation#45's derived Sent match), so it is the honest example:
        // the refusal is what makes adding it a decision rather than a diff.
        let refusal = OvationGmail.refusal(forAsking: [
            "https://www.googleapis.com/auth/gmail.send",
            "https://www.googleapis.com/auth/gmail.readonly",
        ])

        #expect(refusal?.contains("gmail.readonly") == true,
                "the refusal must name the scope, not only that something was wrong")
    }

    @Test("the approved list itself is not refused")
    func theapprovedListPasses() {
        // The positive control. Without it a refusal that always fires would pass
        // the case above (L159).
        #expect(OvationGmail.refusal(forAsking: OvationGmail.approvedScopes) == nil)
    }

    @Test("asking for nothing at all is refused too")
    func anemptyAskIsRefused() {
        // An empty list is a superset of nothing and would pass a membership test
        // written only as "everything asked is approved", while being the state
        // the package itself throws on.
        #expect(OvationGmail.refusal(forAsking: []) != nil)
    }

    // MARK: the package's own refusal, live in this process (ovation#426)

    /// THIS IS NOT A COPY OF backstage's `test-scopes-required.sh`, which proves
    /// the COMPILE error by building a throwaway consumer. This proves the RUNTIME
    /// refusal arrived in the binary Ovation actually links.
    @Test("constructing with no scopes throws, in Ovation's own process")
    func anemptyScopeListThrows() {
        #expect(throws: GmailAuthManager.AuthError.noScopes) {
            _ = try GmailAuthManager(credentialsDirectory: Self.throwawayDirectory, scopes: [],
                                     productName: "Ovation")
        }
    }

    /// WHAT THE MANAGER RESOLVED, NOT THE CONSTANT THE CALL SITE PASSED, and never
    /// `contains`. If the package ever grows a default or a union, a test reading
    /// Ovation's own constant stays green while the app asks Google for more.
    @Test("the manager resolves exactly the approved scopes and nothing beside them")
    func theresolvedScopesAreExactlyTheApprovedOnes() throws {
        let manager = try #require(
            try OvationGmail.authManager(credentialsDirectory: Self.throwawayDirectory))

        #expect(manager.scopes == OvationGmail.approvedScopes)
    }

    @Test("the factory refuses to build one asking for anything unapproved")
    func thefactoryRefusesAnUnapprovedAsk() {
        #expect(throws: OvationGmail.Refusal.self) {
            _ = try OvationGmail.authManager(
                asking: ["https://www.googleapis.com/auth/gmail.modify"],
                credentialsDirectory: Self.throwawayDirectory)
        }
    }

    // MARK: where the credentials live, and when there is nowhere (ovation#425)

    /// THE STRUCTURAL HALF. This suite IS a disposable launch, so the live
    /// resolver must answer nothing here with no arguments passed, exactly as
    /// every other member of the isolation floor does (plan 1.9, ovation#58).
    @Test("there is no live credentials directory inside a test run")
    func nolivedirectoryUnderADisposableLaunch() {
        #expect(StoreLocation.liveCredentialsDirectory() == nil)
    }

    /// AND NO MANAGER EITHER, which is the thing that matters: a factory that
    /// refused the directory and then built a manager over a fallback would be
    /// the fallback reaching Dan's mailbox (L75).
    @Test("and no manager is built inside a test run")
    func nomanagerUnderADisposableLaunch() throws {
        #expect(try OvationGmail.authManager() == nil)
    }

    /// DAN'S DECISION, 2026-09-19: a Debug build may not reach live Google. It is
    /// a separate question from a disposable launch and is asserted separately,
    /// because a Debug build is a REAL run with a real store of its own.
    @Test("a Debug build reaches no live Google, although its store is real",
          arguments: [true, false])
    func adebugBuildReachesNoLiveGoogle(isDebugBuild: Bool) {
        let mayReach = AppEnvironment.mayReachLiveGoogle(environment: [:],
                                                         isDebugBuild: isDebugBuild)

        #expect(mayReach == !isDebugBuild)
        // ASSERTED IN BOTH DIRECTIONS. "nil or not a Debug build" is satisfied by
        // the non Debug arm on its own, so it would pass with the refusal removed.
        #expect((StoreLocation.liveCredentialsDirectory(mayReachLiveGoogle: mayReach) != nil)
                    == mayReach)
    }

    @Test("a disposable launch reaches no live Google whatever kind of build it is",
          arguments: [true, false])
    func adisposableLaunchReachesNoLiveGoogle(isDebugBuild: Bool) {
        let underTest = ["XCTestConfigurationFilePath": "/anywhere"]

        #expect(AppEnvironment.mayReachLiveGoogle(environment: underTest,
                                                  isDebugBuild: isDebugBuild) == false)
    }

    /// A REAL RELEASE RUN DOES GET ONE, which is the positive control the two
    /// cases above need: without it a resolver that always answered nil would pass
    /// both while the feature could never work (L159).
    @Test("a real Release run is given a directory, beside the store and not inside it")
    func arealRunIsGivenADirectory() throws {
        let directory = try #require(
            StoreLocation.liveCredentialsDirectory(mayReachLiveGoogle: true))

        #expect(directory.path.contains("/Ovation/"),
                "it belongs with the rest of Ovation's own state")
        #expect(!directory.path.contains("Ovation-Debug"),
                "a Debug build never reaches here, so it can never be the Debug folder")
        #expect(directory.lastPathComponent != StoreLocation.storeFilename)
    }

    /// Never written to and never created. The manager only computes URLs from it.
    private static let throwawayDirectory = URL.temporaryDirectory
        .appending(path: "ovation-gmail-tests", directoryHint: .isDirectory)
}

/// ovation#42. Gmail for one press of Send, in two steps: building the sender, which
/// opens nothing, and making it ready, which is where a browser can ask Dan to sign
/// in and which the send calls only after every refusal (L667).
///
/// A FAKE CONNECTION, because the real one opens a browser. Each case says what the
/// person reads, since every refusal here stops a send (L11).
@MainActor
struct GmailSenderSetupTests {

    @Test("a build that does not reach Gmail says so")
    func abuildWithoutGmailSaysSo() {
        let result = OvationGmail.sender(for: Self.settings, connection: { nil })
        #expect(Self.refusal(result) == "This build of Ovation does not reach Gmail, so nothing was sent.")
    }

    @Test("a connection that cannot be set up says so")
    func asetupFailureSaysSo() {
        let result = OvationGmail.sender(for: Self.settings,
                                         connection: { throw FakeConnection.Failure.broken })
        #expect(Self.refusal(result)?.hasPrefix("Gmail could not be set up") == true)
        #expect(Self.refusal(result)?.hasSuffix("so nothing was sent.") == true)
    }

    @Test("building the sender connects nothing, however unconnected Gmail is")
    func buildingConnectsNothing() {
        let gmail = FakeConnection(connected: false, connectFails: false)
        _ = OvationGmail.sender(for: Self.settings, connection: { gmail })
        #expect(gmail.connects == 0)
    }

    @Test("making a Gmail not yet connected ready connects it once")
    func readyConnectsOnce() async throws {
        let gmail = FakeConnection(connected: false, connectFails: false)
        let route = try OvationGmail.sender(for: Self.settings, connection: { gmail }).get()
        #expect(await route.ready() == nil)
        #expect(gmail.connects == 1)
    }

    @Test("a connect that fails says so, and it was tried exactly once")
    func afailedConnectSaysSo() async throws {
        let gmail = FakeConnection(connected: false, connectFails: true)
        let route = try OvationGmail.sender(for: Self.settings, connection: { gmail }).get()
        let why = await route.ready()
        #expect(why?.sentence.hasPrefix("Gmail could not be connected") == true)
        #expect(gmail.connects == 1)
    }

    @Test("a Gmail already connected is not asked to connect again")
    func aconnectedGmailIsLeftAlone() async throws {
        let gmail = FakeConnection(connected: true, connectFails: false)
        let route = try OvationGmail.sender(for: Self.settings, connection: { gmail }).get()
        #expect(await route.ready() == nil)
        #expect(gmail.connects == 0)
    }

    private static let settings = SendingSettings(fromName: "Dan Wright", fromEmail: "dan@studio.example",
                                                  destination: .clients)

    private static func refusal(_ result: Result<SendingRoute, SenderUnavailable>) -> String? {
        if case .failure(let why) = result { return why.sentence }
        return nil
    }
}

@MainActor
final class FakeConnection: GmailSignIn {
    enum Failure: Error { case broken }
    private(set) var isConnected: Bool
    private let connectFails: Bool
    private(set) var connects = 0

    init(connected: Bool, connectFails: Bool) {
        isConnected = connected
        self.connectFails = connectFails
    }

    func connectNow() async throws {
        connects += 1
        if connectFails { throw Failure.broken }
        isConnected = true
    }

    func validAccessToken() async throws -> String { "token" }
    func signalAuthExpired() throws {}
}

/// ovation#577. What backstage 0.5.0 changed that Ovation's own send path meets.
///
/// 0.4.0 made the stored grant the one Google REPORTED rather than the one asked
/// for (backstage#68), and 0.5.0 told a client file that is there but unusable
/// apart from one that is absent (backstage#70). Both arrive in Ovation through
/// `validAccessToken`, which is what every send calls, so these drive that call
/// with Ovation's own scopes against a throwaway credentials folder and a fake
/// network, and assert the sentence Dan would read (L263).
///
/// AND THE INSTALLED APP'S OWN SHAPE, which is the case that decides whether the
/// move is safe to ship: a token as 0.3.0 saved it must still hand out its access
/// token with no new sign in and no network. The token file format did not change
/// between the two versions, and this is what proves that rather than a reading
/// of the diff (L1013).
@MainActor
struct BackstageGrantTests {

    @Test("a client file that is there but a placeholder is refused as unusable, naming the field")
    func aplaceholderClientIsUnusable() async throws {
        try await Self.inFolder(client: #"{"clientId":"PASTE_CLIENT_ID_HERE","clientSecret":"x"}"#) { folder in
            let manager = try #require(try OvationGmail.authManager(credentialsDirectory: folder))

            await #expect {
                _ = try await manager.validAccessToken()
            } throws: { error in
                guard case GmailAuthManager.AuthError.clientConfigUnusable = error else { return false }
                return error.localizedDescription.contains("clientId")
            }
        }
    }

    @Test("a missing client file is still the missing configuration, not an unusable one")
    func amissingClientIsStillMissing() async throws {
        // The positive control for the case above: a refusal that fired on every
        // file would pass it while telling Dan to go and find a file he has (L159).
        try await Self.inFolder(client: nil) { folder in
            let manager = try #require(try OvationGmail.authManager(credentialsDirectory: folder))

            await #expect(throws: GmailAuthManager.AuthError.noClientConfig) {
                _ = try await manager.validAccessToken()
            }
        }
    }

    @Test("a refresh that Google answers with less than gmail.send is refused naming gmail.send")
    func anarrowedRefreshIsRefused() async throws {
        try await Self.inFolder(client: Self.usableClient()) { folder in
            try Self.saveToken(in: folder, accessToken: nil, granted: OvationGmail.approvedScopes)
            let manager = try Self.manager(in: folder, reply: #"{"access_token":"new","expires_in":3599,"scope":"https://www.googleapis.com/auth/gmail.readonly","token_type":"Bearer"}"#)

            await #expect(throws: GmailAuthManager.AuthError.scopesNotGranted(OvationGmail.approvedScopes)) {
                _ = try await manager.validAccessToken()
            }
        }
    }

    @Test("a refresh whose reply names no scope is refused rather than read as the request")
    func anunreportedGrantIsRefused() async throws {
        try await Self.inFolder(client: Self.usableClient()) { folder in
            try Self.saveToken(in: folder, accessToken: nil, granted: OvationGmail.approvedScopes)
            let manager = try Self.manager(in: folder, reply: #"{"access_token":"new","expires_in":3599,"token_type":"Bearer"}"#)

            await #expect(throws: GmailAuthManager.AuthError.grantUnreported) {
                _ = try await manager.validAccessToken()
            }
        }
    }

    @Test("a refresh granting gmail.send hands out the new token")
    func acoveringRefreshSucceeds() async throws {
        // The positive control for both refusals above (L159).
        try await Self.inFolder(client: Self.usableClient()) { folder in
            try Self.saveToken(in: folder, accessToken: nil, granted: OvationGmail.approvedScopes)
            let manager = try Self.manager(in: folder, reply: #"{"access_token":"new","expires_in":3599,"scope":"https://www.googleapis.com/auth/gmail.send","token_type":"Bearer"}"#)

            #expect(try await manager.validAccessToken() == "new")
        }
    }

    @Test("a token as the installed app saved it still sends, with no sign in and no network")
    func theinstalledShapeStillWorks() async throws {
        try await Self.inFolder(client: Self.usableClient()) { folder in
            try Self.saveToken(in: folder, accessToken: "saved", granted: OvationGmail.approvedScopes)
            let manager = try Self.manager(in: folder, reply: nil)

            #expect(try await manager.validAccessToken() == "saved")
            #expect(manager.isConnected)
        }
    }

    @Test("the credentials folder a case used is gone once it returns")
    func thefolderIsRemovedAfterACase() async throws {
        var used: URL?
        try await Self.inFolder(client: Self.usableClient()) { folder in
            try Self.saveToken(in: folder, accessToken: "saved", granted: OvationGmail.approvedScopes)
            used = folder
            #expect(FileManager.default.fileExists(atPath: GmailCredentials.tokenURL(in: folder).path))
        }
        let folder = try #require(used)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    @Test("and gone when the case throws, which is the exit a failing case takes")
    func thefolderIsRemovedAfterAThrow() async throws {
        enum Stop: Error { case stop }
        var used: URL?
        await #expect(throws: Stop.stop) {
            try await Self.inFolder(client: Self.usableClient()) { folder in
                used = folder
                throw Stop.stop
            }
        }
        let folder = try #require(used)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    // A CLIENT IN THE SHAPE GOOGLE ISSUES, since 0.4.0 refuses anything else
    // (backstage#67): an id with Google's suffix and a secret of its prefix and
    // length. Invented, and ASSEMBLED FROM PIECES as backstage's own fixture is,
    // because a literal of the real shape is what a secret scanner exists to
    // refuse and it cannot tell a made up value from a leaked one.
    private static func usableClient() throws -> String {
        let client = GmailClient(clientId: "123456789012-" + "fixture" + ".apps.googleusercontent.com",
                                 clientSecret: "GOCSPX" + "-" + String(repeating: "f", count: 28))
        return String(decoding: try JSONEncoder().encode(client), as: UTF8.self)
    }

    private enum NetworkTouched: Error { case touched }

    /// A folder of its own under the system temporary directory, which is the
    /// throwaway root backstage lets a test run write credentials into
    /// (backstage#44), handed to `body` and REMOVED on every way out of it,
    /// returning or throwing. Each case writes a client file and a token here, and
    /// a folder left behind per case per run is credential shaped files piling up
    /// in the temporary directory for ever.
    static func inFolder(client: String?,
                         _ body: @MainActor (URL) async throws -> Void) async throws {
        let folder = URL.temporaryDirectory
            .appending(path: "ovation-grant-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        if let client {
            try Data(client.utf8).write(to: GmailCredentials.clientConfigURL(in: folder))
        }
        try await body(folder)
    }

    private static func saveToken(in folder: URL, accessToken: String?, granted: [String]) throws {
        let now = Date()
        let tokens = StoredTokens(refreshToken: "refresh", accessToken: accessToken,
                                  accessTokenExpiry: accessToken == nil ? nil : now.addingTimeInterval(3600),
                                  grantedScopes: granted, obtainedAt: now, lastConfirmedAt: now)
        #expect(try GmailCredentials.saveTokens(tokens, to: GmailCredentials.tokenURL(in: folder)))
    }

    /// Ovation's own scopes over a fake network that answers `reply`, or fails the
    /// case by throwing when `reply` is nil and the network is reached at all.
    private static func manager(in folder: URL, reply: String?) throws -> GmailAuthManager {
        try GmailAuthManager(credentialsDirectory: folder, scopes: OvationGmail.approvedScopes,
                             productName: "Ovation",
                             fetch: { request in
                                 guard let reply else { throw NetworkTouched.touched }
                                 let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                                                httpVersion: nil, headerFields: nil)!
                                 return (Data(reply.utf8), response)
                             })
    }
}
