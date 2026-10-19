import Foundation

/// A launch request only. A complication tap never creates an empty sample.
public enum WatchLogShortcut {
    public static let scheme = "canal-dash"
    public static let url = URL(string: "canal-dash://log-now")!

    public static func matches(_ url: URL) -> Bool {
        url.scheme?.lowercased() == scheme && url.host?.lowercased() == "log-now" &&
        ["", "/"].contains(url.path) && url.query == nil && url.fragment == nil &&
        url.user == nil && url.password == nil && url.port == nil
    }
}
