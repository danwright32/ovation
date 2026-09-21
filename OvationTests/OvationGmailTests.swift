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
            _ = try GmailAuthManager(credentialsDirectory: Self.throwawayDirectory, scopes: [])
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
