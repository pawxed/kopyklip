import AVFoundation
import AVKit
import Combine
import UIKit

final class PipDisplayView: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }

    var sampleLayer: AVSampleBufferDisplayLayer {
        layer as! AVSampleBufferDisplayLayer
    }
}

final class PipClipboardMonitor: NSObject, ObservableObject {
    static let shared = PipClipboardMonitor()

    @Published private(set) var isMonitoring = false

    private let displayView = PipDisplayView()
    private var controller: AVPictureInPictureController?
    private var timer: Timer?
    private var lastChange = UIPasteboard.general.changeCount
    private var paused = false
    private var latestText = "Monitoring clipboard"

    private var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }

    func start() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try? session.setActive(true)

        if displayView.superview == nil {
            displayView.frame = CGRect(x: 0, y: 0, width: 1200, height: 120)
            displayView.alpha = 0.01
            displayView.isUserInteractionEnabled = false
            keyWindow?.addSubview(displayView)
        }
        render()

        guard controller == nil else { return }
        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayView.sampleLayer,
            playbackDelegate: self
        )
        let pip = AVPictureInPictureController(contentSource: source)
        pip.delegate = self
        pip.requiresLinearPlayback = true
        pip.canStartPictureInPictureAutomaticallyFromInline = true
        controller = pip
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.controller === pip, pip.isPictureInPicturePossible else { return }
            pip.startPictureInPicture()
        }
    }

    func stop() {
        stopPolling()
        controller?.stopPictureInPicture()
        controller = nil
        displayView.removeFromSuperview()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isMonitoring = false
    }

    private func startPolling() {
        guard timer == nil else { return }
        lastChange = UIPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.check()
        }
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private func check() {
        let pasteboard = UIPasteboard.general
        guard pasteboard.changeCount != lastChange else { return }
        lastChange = pasteboard.changeCount
        guard let text = pasteboard.string, !text.isEmpty else { return }
        KopyStore.addClip(text)
        latestText = text
        render()
    }

    private func render() {
        let size = CGSize(width: 1200, height: 120)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let text = NSAttributedString(string: String(latestText.prefix(90)), attributes: [
                .font: UIFont.systemFont(ofSize: 32),
                .foregroundColor: UIColor.white
            ])
            text.draw(at: CGPoint(x: 20, y: 40))
        }
        guard let pixel = pixelBuffer(from: image), let sample = sampleBuffer(from: pixel) else { return }
        if displayView.sampleLayer.controlTimebase == nil {
            var timebase: CMTimebase?
            if CMTimebaseCreateWithSourceClock(allocator: nil, sourceClock: CMClockGetHostTimeClock(), timebaseOut: &timebase) == noErr,
               let timebase {
                CMTimebaseSetRate(timebase, rate: 1)
                displayView.sampleLayer.controlTimebase = timebase
            }
        }
        displayView.sampleLayer.enqueue(sample)
    }

    private func pixelBuffer(from image: UIImage) -> CVPixelBuffer? {
        let width = Int(image.size.width)
        let height = Int(image.size.height)
        var buffer: CVPixelBuffer?
        let options: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            options as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess, let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        )
        context?.draw(image.cgImage!, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    private func sampleBuffer(from pixel: CVPixelBuffer) -> CMSampleBuffer? {
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: nil,
            imageBuffer: pixel,
            formatDescriptionOut: &format
        ) == noErr, let format else { return nil }
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 1),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: nil,
            imageBuffer: pixel,
            formatDescription: format,
            sampleTiming: &timing,
            sampleBufferOut: &sample
        ) == noErr, let sample else { return nil }
        return sample
    }
}

extension PipClipboardMonitor: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        paused = false
        isMonitoring = true
        startPolling()
        render()
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        stopPolling()
        isMonitoring = false
    }
}

extension PipClipboardMonitor: AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .zero, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        paused
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        paused = !playing
        if playing { startPolling() } else { stopPolling() }
        render()
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping @Sendable () -> Void) {
        completionHandler()
    }

}
