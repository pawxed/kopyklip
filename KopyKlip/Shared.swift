import CoreFoundation
import Foundation
import UIKit

enum StoreChange {
    static let darwinName = "com.pawxed.kopyklip.storeChanged"
    static let notification = Notification.Name("KopyStoreChanged")
    static let pipName = "com.pawxed.kopyklip.pipCaptured"
    static let pipNotification = Notification.Name("KopyPipCaptured")

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
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, _, _, _ in
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: StoreChange.pipNotification, object: nil)
                }
            },
            pipName as CFString,
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

    static func postPip() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(pipName as CFString),
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
    let image: String?

    init(text: String) {
        self.id = UUID()
        self.text = text
        self.date = Date()
        self.image = nil
    }

    init(image: String) {
        self.id = UUID()
        self.text = ""
        self.date = Date()
        self.image = image
    }

    var isImage: Bool { image != nil }
}

private struct StoreState: Codable {
    var change: Int
    var clips: [Clip]
}

enum ClipBridge {
    static let port: UInt16 = 51789

    static var url: URL {
        URL(string: "http://127.0.0.1:\(port)/clips")!
    }

    static func fetch(_ completion: @escaping ([Clip]) -> Void) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.5
        request.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data, let clips = try? JSONDecoder().decode([Clip].self, from: data) else {
                completion([])
                return
            }
            completion(clips)
        }.resume()
    }

    static func delete(_ id: UUID) {
        send("/delete?id=\(id.uuidString)")
    }

    static func clear() {
        send("/clear")
    }

    private static func send(_ path: String) {
        guard let url = URL(string: "http://127.0.0.1:\(port)\(path)") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.5
        request.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: request).resume()
    }
}

enum KopyStore {
    static let groupID = "group.com.pawxed.kopyklip"
    static let maxClips = 50

    static var isShared: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) != nil
    }

    static var directory: URL {
        if let shared = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
            return shared
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static var stateURL: URL { directory.appendingPathComponent("state.json") }
    private static var imagesURL: URL { directory.appendingPathComponent("images", isDirectory: true) }

    static func clips() -> [Clip] {
        load().clips
    }

    static func image(for clip: Clip) -> UIImage? {
        guard let name = clip.image else { return nil }
        return UIImage(contentsOfFile: imagesURL.appendingPathComponent(name).path)
    }

    @discardableResult
    static func capturePasteboard() -> Clip? {
        let pasteboard = UIPasteboard.general
        let change = pasteboard.changeCount
        guard change != load().change else { return nil }

        if let text = pasteboard.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            let clip = Clip(text: text)
            commit(clip, change: change)
            return clip
        }
        if let image = pasteboard.image, let name = saveImage(image) {
            let clip = Clip(image: name)
            commit(clip, change: change)
            return clip
        }
        return nil
    }

    static func markHandled() {
        var state = load()
        state.change = UIPasteboard.general.changeCount
        save(state)
    }

    static func removeClip(id: UUID) {
        var state = load()
        guard let removed = state.clips.first(where: { $0.id == id }) else { return }
        state.clips.removeAll { $0.id == id }
        deleteImage(removed)
        save(state)
        StoreChange.post()
    }

    static func clearClips() {
        var state = load()
        state.clips.forEach(deleteImage)
        state.clips = []
        state.change = UIPasteboard.general.changeCount
        save(state)
        StoreChange.post()
    }

    private static func commit(_ clip: Clip, change: Int) {
        var state = load()
        state.change = change
        if clip.isImage {
            state.clips.removeAll { $0.image == clip.image }
        } else {
            state.clips.removeAll { $0.text == clip.text }
        }
        state.clips.insert(clip, at: 0)
        if state.clips.count > maxClips {
            state.clips[maxClips...].forEach(deleteImage)
            state.clips = Array(state.clips.prefix(maxClips))
        }
        save(state)
        StoreChange.post()
    }

    private static func load() -> StoreState {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(StoreState.self, from: data) else {
            return StoreState(change: -1, clips: [])
        }
        return state
    }

    private static func save(_ state: StoreState) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

    private static func saveImage(_ image: UIImage) -> String? {
        guard let data = downscale(image).jpegData(compressionQuality: 0.8) else { return nil }
        try? FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true)
        let name = UUID().uuidString + ".jpg"
        guard (try? data.write(to: imagesURL.appendingPathComponent(name))) != nil else { return nil }
        return name
    }

    private static func deleteImage(_ clip: Clip) {
        guard let name = clip.image else { return }
        try? FileManager.default.removeItem(at: imagesURL.appendingPathComponent(name))
    }

    private static func downscale(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > 1024 else { return image }
        let scale = 1024 / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
