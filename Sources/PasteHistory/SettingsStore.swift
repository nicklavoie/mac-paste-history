import Foundation

final class SettingsStore {
    private enum Keys {
        static let hotKey = "hotKey"
    }

    private let defaults = UserDefaults.standard

    var hotKey: HotKey {
        get {
            guard let data = defaults.data(forKey: Keys.hotKey),
                  let hotKey = try? JSONDecoder().decode(HotKey.self, from: data) else {
                return .defaultShortcut
            }
            return hotKey
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.hotKey)
            }
        }
    }
}
