import Foundation
import SquishPolicy

/// Remote switches (ad pacing, the Christmas date, an off switch per extra).
/// One plain GET of a static file: no cookies, no identifiers, nothing about the
/// player. The last good copy is cached, and anything unreadable means defaults.
enum RemoteConfig {
    static let url = URL(string: "https://squishsort.app/config.json")!

    private static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }

    private static var isUITesting: Bool { ProcessInfo.processInfo.arguments.contains("-uiTesting") }

    /// What the last launch fetched, or the bundled defaults.
    static func cached() -> GameConfig {
        if isUITesting { return GameConfig() }
        return GameConfig.decodeOrDefault(try? Data(contentsOf: cacheURL))
    }

    /// Nil when offline, on any error, or when the file isn't valid config.
    static func fetch() async -> GameConfig? {
        if isUITesting { return nil }
        let session = URLSession(configuration: .ephemeral)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.httpShouldHandleCookies = false
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              data.count < 100_000,
              let config = try? JSONDecoder().decode(GameConfig.self, from: data) else { return nil }
        try? data.write(to: cacheURL, options: .atomic)
        return config
    }
}
