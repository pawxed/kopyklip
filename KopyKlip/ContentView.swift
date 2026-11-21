import AVKit
import SwiftUI

struct ContentView: View {
    @ObservedObject private var monitor = PipClipboardMonitor.shared

    var body: some View {
        NavigationStack {
            List {
                Section("How to use") {
                    Text("1. Go to Settings > General > Keyboard > Keyboards > Add New Keyboard > KopyKlip.")
                    Text("2. Turn on Full Access so the keyboard can read copied text.")
                    Text("3. Copy text anywhere. It appears in the keyboard next time you open it.")
                    Text("4. Switch to the KopyKlip keyboard with the globe key.")
                    Text("5. Tap a clip to insert it into the field you are typing in.")
                    Text("6. Swipe a clip left to delete just that clip.")
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
                    Text("Shows a wide, thin Picture in Picture banner that keeps watching the clipboard even after you leave the app. Close the banner to stop.")
                }

            }
            .navigationTitle("KopyKlip")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            KopyStore.capturePasteboard()
        }
    }
}
