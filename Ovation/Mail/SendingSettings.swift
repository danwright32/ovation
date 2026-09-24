// ovation#42. Where Ovation's own sends go, and who they are from.
//
// READ FROM A FILE ON DAN'S MAC, never from this repository. The repository is public
// and `docs/PRIVACY-FLOOR.md` forbids a real address in the tree, so the sending
// address and the address the first real send is redirected to cannot be constants,
// fixtures or defaults in `project.yml`. They arrive at run time.
//
// THE DESTINATION FAILS CLOSED. The first draft of the plan had an environment variable
// whose ABSENCE meant "send to the real client", which is the inverted default: a
// forgotten setting produced the live outcome (L42, L72), and a variable does nothing
// to an app already running. So the send refuses until a destination is written down,
// and no missing or unreadable value can resolve to a client.
//
// THE FILE, which Dan edits and nothing in the app writes:
//
//     {"fromName": "...", "fromEmail": "...", "destination": "test", "testAddress": "..."}
//     {"fromName": "...", "fromEmail": "...", "destination": "clients"}
//
// ONE VALUE NAMES WHERE IT GOES. `SendDestination` is handed to both the review sheet
// and the sender, so what Dan approves and where the message goes cannot disagree
// (L64, L455), and a redirected send is recorded as one on the attempt (ovation#460).
import Foundation

struct SendingSettings: Equatable, Sendable {
    let fromName: String
    let fromEmail: String
    let destination: SendDestination

    /// The settings in the file, or the reason there are none.
    ///
    /// Every field is required and a blank one is a missing one: a half-filled template
    /// is what a present, empty field looks like (L67, L138, L688).
    static func read(from url: URL) -> Result<SendingSettings, SendingSettingsRefusal> {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failure(.noFile(path: url.path))
        }
        let object: [String: Any]
        do {
            let data = try Data(contentsOf: url)
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure(.unreadable(detail: "it is not a JSON object"))
            }
            object = parsed
        } catch {
            return .failure(.unreadable(detail: error.localizedDescription))
        }

        func field(_ name: String) -> String? {
            guard let value = (object[name] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return value
        }

        guard let fromName = field("fromName") else { return .failure(.missing(field: "fromName")) }
        guard let fromEmail = field("fromEmail") else { return .failure(.missing(field: "fromEmail")) }
        guard isOneAddress(fromEmail) else { return .failure(.notAnAddress(field: "fromEmail")) }
        guard let destination = field("destination") else {
            return .failure(.missing(field: "destination"))
        }

        switch destination {
        case "clients":
            return .success(SendingSettings(fromName: fromName, fromEmail: fromEmail,
                                            destination: .clients))
        case "test":
            guard let address = field("testAddress") else {
                return .failure(.missing(field: "testAddress"))
            }
            guard isOneAddress(address) else { return .failure(.notAnAddress(field: "testAddress")) }
            return .success(SendingSettings(fromName: fromName, fromEmail: fromEmail,
                                            destination: .testAddress(address)))
        default:
            // AN UNKNOWN VALUE IS REFUSED, never read as either known one: "client" for
            // "clients" is the typo that would otherwise send a test to a real client.
            return .failure(.unknownDestination(destination))
        }
    }

    /// One address the send path can take: exactly one `@` and no whitespace, the same
    /// rule the client's own addresses are held to.
    private static func isOneAddress(_ value: String) -> Bool {
        value.filter { $0 == "@" }.count == 1 && !value.contains(where: { $0.isWhitespace })
    }
}

/// Where a send goes.
enum SendDestination: Equatable, Sendable {
    /// Every send goes to this one address instead of the client, which is how the
    /// first real send is made without a client receiving a test (Dan, 2026-09-21).
    case testAddress(String)
    /// Sends go to the client's own recipients.
    case clients

    /// Who a send to this client actually goes to.
    func recipients(forClient client: [String]) -> [String] {
        switch self {
        case .testAddress(let address): return [address]
        case .clients: return client
        }
    }

    /// Whether the message goes somewhere other than the client, recorded on the attempt
    /// together with where it went, never as a flag beside it (L544).
    var isRedirected: Bool {
        if case .testAddress = self { return true }
        return false
    }

    /// What the review sheet says when a send will not reach the client, or nil when it
    /// will. Derived here, so the sheet cannot say one thing while the send does another.
    var warning: String? {
        switch self {
        case .testAddress(let address):
            return "This goes to your test address, \(address), not to the client."
        case .clients:
            return nil
        }
    }
}

/// Why there are no sending settings. Each needs something different from Dan (L11).
enum SendingSettingsRefusal: Error, Equatable {
    case noFile(path: String)
    case unreadable(detail: String)
    case missing(field: String)
    case notAnAddress(field: String)
    case unknownDestination(String)

    var sentence: String {
        switch self {
        case .noFile(let path):
            return "Nothing can be sent until Ovation is told where sends go and who they are from, in \(path)."
        case .unreadable(let detail):
            return "The sending settings could not be read, so nothing can be sent: \(detail)."
        case .missing(let field):
            return "The sending settings have no \(field), so nothing can be sent."
        case .notAnAddress(let field):
            return "The sending settings' \(field) is not one email address, so nothing can be sent."
        case .unknownDestination(let value):
            return "The sending settings say to send to \"\(value)\", which is neither test nor clients, so nothing can be sent."
        }
    }
}
