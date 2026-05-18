import Foundation

final class PreferenceSync {
    static let shared = PreferenceSync()

    private let kv   = NSUbiquitousKeyValueStore.default
    private let keys = ["defaultReadMode", "rtlMode", "appColorScheme", "autoplayInterval"]

    private init() {}

    func start() {
        kv.synchronize()
        pullFromCloud()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cloudChanged(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kv
        )
    }

    func push(key: String) {
        guard keys.contains(key) else { return }
        kv.set(UserDefaults.standard.object(forKey: key), forKey: key)
    }

    private func pullFromCloud() {
        for key in keys {
            guard let remote = kv.object(forKey: key) else { continue }
            let local = UserDefaults.standard.object(forKey: key)
            if !equal(remote, local) {
                UserDefaults.standard.set(remote, forKey: key)
            }
        }
    }

    @objc private func cloudChanged(_ note: Notification) {
        guard let changed = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] else { return }
        for key in changed where keys.contains(key) {
            if let val = kv.object(forKey: key) {
                UserDefaults.standard.set(val, forKey: key)
            }
        }
    }

    private func equal(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case let (a as Bool,   b as Bool):   return a == b
        case let (a as Double, b as Double): return a == b
        case let (a as String, b as String): return a == b
        case (nil, nil):                     return true
        default:                             return false
        }
    }
}
