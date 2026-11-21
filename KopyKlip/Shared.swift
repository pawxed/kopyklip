import CoreFoundation
import Foundation
import UIKit

enum StoreChange {
    static let darwinName = "com.pawxed.kopyklip.storeChanged"
    static let notification = Notification.Name("KopyStoreChanged")

    private static let install: Void = {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, _, _, _ in
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: StoreChange.notification, object: nil)
                }
            },
            darwinName as CFString,
            nil,
            .deliverImmediately
        )
    }()

    static func start() {
        _ = install
    }

    static func post() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(darwinName as CFString),
            nil,
            nil,
            true
        )
    }
}

struct Clip: Codable, Identifiable, Hashable {
    let id: UUID
    let text: String
    let date: Date

    init(text: String) {
        self.id = UUID()
        self.text = text
        self.date = Date()
    }
}

enum KopyStore {
    static let groupID = "group.com.pawxed.kopyklip"
    static let maxClips = 50

    private static let defaults = UserDefaults(suiteName: groupID)
    private static let clipsKey = "clips"
    private static let changeKey = "pasteboardChange"

    private static var lastChange: Int {
        get {
            defaults?.synchronize()
            return defaults?.integer(forKey: changeKey) ?? -1
        }
        set {
            defaults?.set(newValue, forKey: changeKey)
            defaults?.synchronize()
        }
    }

    static func clips() -> [Clip] {
        defaults?.synchronize()
        guard let data = defaults?.data(forKey: clipsKey),
              let items = try? JSONDecoder().decode([Clip].self, from: data) else { return [] }
        return items
    }

    static func capturePasteboard() {
        let pasteboard = UIPasteboard.general
        guard pasteboard.changeCount != lastChange else { return }
        lastChange = pasteboard.changeCount
        guard let text = pasteboard.string, !text.isEmpty else { return }
        addClip(text)
    }

    static func addClip(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let store = defaults else { return }
        var items = clips().filter { $0.text != trimmed }
        items.insert(Clip(text: trimmed), at: 0)
        guard let data = try? JSONEncoder().encode(Array(items.prefix(maxClips))) else { return }
        store.set(data, forKey: clipsKey)
        store.synchronize()
        StoreChange.post()
    }

    static func removeClip(id: UUID) {
        guard let store = defaults else { return }
        let items = clips().filter { $0.id != id }
        guard let data = try? JSONEncoder().encode(items) else { return }
        store.set(data, forKey: clipsKey)
        store.synchronize()
        StoreChange.post()
    }

    static func clearClips() {
        guard let store = defaults else { return }
        store.removeObject(forKey: clipsKey)
        lastChange = UIPasteboard.general.changeCount
        store.synchronize()
        StoreChange.post()
    }
}
