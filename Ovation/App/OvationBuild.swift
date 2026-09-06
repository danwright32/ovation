/// Facts about the running build that more than one place needs to agree on.
///
/// This exists so the pure test target has something real from the app module to
/// assert against, which is the whole claim the unhosted design makes: the app's
/// sources are COMPILED IN rather than reached through a launched host. If that
/// ever stopped being true, the suite would fail to build rather than quietly
/// testing nothing.
enum OvationBuild {
    static let displayName = "Ovation"

    /// The one window's identity. Named rather than inlined because plan 1.13's
    /// menu bar item and URL handler both have to bring THIS window forward, and
    /// two spellings of the identifier would silently open a second one.
    static let mainWindowID = "ovation.main"

}
