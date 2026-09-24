// ovation#425 and ovation#426. THE ONE PLACE OVATION CONSTRUCTS A GMAIL AUTH
// MANAGER, and the scopes it is allowed to ask Google for.
//
// THE APP'S SEND CALLS IT, through `sender(for:connection:)` below (ovation#42).
// `scripts/check-forbidden-constructs.sh` refuses a second construction anywhere
// else in the tree, so "one call site" stays true rather than being a sentence in
// a header.
//
// AN ALLOW LIST, NEVER A DENY LIST of Google's restricted scopes. A deny list has
// to mirror Google's policy by hand, permanently exempts anything they reclassify,
// and is named for the question it appears to answer (L41, L257, L42, L72). So the
// question asked here is "was this approved", and the answer for anything not
// written below is no.
//
// WHY THE LIST IS ONLY `gmail.send` TODAY. Verified 2026-09-19: `gmail.send` is a
// SENSITIVE scope, while `gmail.readonly`, `gmail.metadata` and `gmail.modify` are
// RESTRICTED. Reading and modifying get added by the issues that need them,
// ovation#41 and ovation#45 for the derived Sent match and ovation#75 for the
// receipts route, each paying that cost knowingly rather than inheriting it.
//
// THE PACKAGE SUPPLIES NO DEFAULT, which is the whole reason it was extracted
// (backstage#3): a consumer that names no scopes does not compile, and an empty
// list is refused at runtime. Ovation names its own here, once.
import BackstageGoogle
import Foundation

enum OvationGmail {

    /// Why a set of scopes was refused.
    ///
    /// ITS OWN TYPE rather than a bool, because the message has to name the scope
    /// that was not approved: a refusal that says only "no" leaves whoever hit it
    /// reading this file to find out which one (L11).
    enum Refusal: Error, Equatable {
        /// Asked for scopes nobody approved, named.
        case notApproved([String])
        /// Asked for nothing at all, which the package itself throws on.
        case nothingAsked
    }

    /// Every scope Ovation is approved to ask Google for.
    ///
    /// AN ORDERED LIST RATHER THAN A SET, because ovation#426 asserts the scopes
    /// the manager RESOLVED against this exactly, and a set has no order to
    /// compare (L343, L339).
    static let approvedScopes: [String] = [
        "https://www.googleapis.com/auth/gmail.send",
    ]

    /// Why this ask is refused, or nil where every scope in it is approved.
    static func refusal(forAsking scopes: [String]) -> String? {
        switch check(scopes) {
        case .none: return nil
        case .some(.nothingAsked):
            return "Ovation asked Google for no scopes at all, which grants nothing."
        case .some(.notApproved(let unapproved)):
            return "Ovation is not approved to ask Google for "
                + unapproved.sorted().joined(separator: ", ")
                + ". Add it to OvationGmail.approvedScopes, knowing what it costs."
        }
    }

    /// The one construction of a Gmail auth manager in Ovation.
    ///
    /// - Parameters:
    ///   - asking: the scopes this manager is for. Defaults to everything
    ///     approved, and anything outside that is refused rather than passed on.
    ///   - credentialsDirectory: where the token and client configuration live, or
    ///     nil where this run may not reach live Google at all.
    /// - Returns: nil where there is no live credentials directory, which is every
    ///   disposable launch and every Debug build.
    ///
    /// NIL RATHER THAN A FALLBACK DIRECTORY. When identifying what an outward
    /// action targets fails, the action is refused; it never falls back to a
    /// nearby candidate, because the nearby candidate here is Dan's real mailbox
    /// (L75). Nil and "a manager over a throwaway folder" are different things to
    /// return and only one of them is honest.
    ///
    /// IT DOES NOT CONNECT AND IT OPENS NO BROWSER. Constructing computes two file
    /// URLs and nothing else, so this is safe to call from anywhere that is not a
    /// launch. Signing in is `connect()`, which ovation#42 owns.
    @MainActor
    static func authManager(
        asking scopes: [String] = approvedScopes,
        credentialsDirectory: URL? = StoreLocation.liveCredentialsDirectory()
    ) throws -> GmailAuthManager? {
        if let refusal = check(scopes) { throw refusal }
        guard let credentialsDirectory else { return nil }
        // THE PRODUCT NAME IS WHAT GOOGLE'S BROWSER TAB IS SENT BACK TO SAY, and
        // backstage 0.3.0 requires it rather than defaulting it (backstage#61).
        return try GmailAuthManager(credentialsDirectory: credentialsDirectory,
                                    scopes: scopes, productName: "Ovation")
    }

    /// A Gmail sender for one press of Send, or the sentence saying why there is none.
    ///
    /// Connects first when Gmail is not connected, which is the moment the browser
    /// asks Dan to sign in; the first send is where that happens, never at launch.
    /// Every way this can end short of a sender stops the send and says which one
    /// (L11): a build that may not reach Gmail, a connection that could not be made
    /// ready, and a sign in that did not finish.
    @MainActor
    static func sender(for settings: SendingSettings,
                       connection make: @MainActor () throws -> (any GmailSignIn)?) async
        -> Result<any MailSender, SenderUnavailable> {
        let gmail: any GmailSignIn
        do {
            guard let made = try make() else {
                return .failure(SenderUnavailable(sentence: "This build of Ovation does not reach Gmail, so nothing was sent."))
            }
            gmail = made
        } catch {
            return .failure(SenderUnavailable(sentence: "Gmail could not be set up (\(error.localizedDescription)), so nothing was sent."))
        }
        if !gmail.isConnected {
            do {
                try await gmail.connectNow()
            } catch {
                return .failure(SenderUnavailable(sentence: "Gmail could not be connected (\(error.localizedDescription)), so nothing was sent."))
            }
        }
        return .success(GmailSender(fromName: settings.fromName, fromEmail: settings.fromEmail,
                                    token: { try await gmail.validAccessToken() },
                                    onAuthExpired: { try? await gmail.signalAuthExpired() }))
    }

    /// The one predicate both the sentence and the factory read, so a scope the
    /// message calls unapproved cannot be one the factory passes on (L16, L70).
    private static func check(_ scopes: [String]) -> Refusal? {
        guard !scopes.isEmpty else { return .nothingAsked }
        let unapproved = scopes.filter { !approvedScopes.contains($0) }
        return unapproved.isEmpty ? nil : .notApproved(unapproved)
    }
}

/// What sending needs from a Gmail sign in, so the send's own setup can be tested
/// without a browser. `GmailAuthManager` is the only real one.
@MainActor
protocol GmailSignIn: AnyObject, Sendable {
    var isConnected: Bool { get }
    func connectNow() async throws
    func validAccessToken() async throws -> String
    func signalAuthExpired() throws
}

extension GmailAuthManager: GmailSignIn {
    func connectNow() async throws { try await connect() }
}
