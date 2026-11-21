import AVKit
import Combine
import SwiftUI
import UIKit

struct ContentView: View {
    @ObservedObject private var monitor = PipClipboardMonitor.shared

    var body: some View {
        NavigationStack {
            List {
                Section("How to use") {
                    Text("1. Go to Settings > General > Keyboard > Keyboards > Add New Keyboard > KopyKlip.")
                    Text("2. Turn on Full Access so the keyboard can read copied text.")
                    Text("3. Copy text or an image anywhere. It is saved when you open KopyKlip or the keyboard.")
                    Text("4. Switch to the KopyKlip keyboard with the globe key.")
                    Text("5. Tap a text clip to insert it. Tap an image clip to copy it, then paste.")
                    Text("6. Swipe a clip left to delete just that clip.")
                    Text("If iOS asks about pasting, go to Settings > KopyKlip and allow Paste from Other Apps.")
                }

                Section("Background monitoring") {
                    Button(monitor.isMonitoring ? "Stop Monitoring" : "Start Monitoring") {
                        if monitor.isMonitoring {
                            monitor.stop()
                        } else {
                            monitor.start()
                        }
                    }
                    .disabled(!AVPictureInPictureController.isPictureInPictureSupported())
                    Text("Shows a wide, thin Picture in Picture banner of the newest clip. iOS blocks reading the clipboard from a background app, so the banner mirrors the list rather than capturing copies.")
                }

            }
            .navigationTitle("KopyKlip")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            KopyStore.capturePasteboard()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
            KopyStore.capturePasteboard()
        }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            KopyStore.capturePasteboard()
        }
        .onAppear {
            ClipServer.shared.start()
        }
    }
}
