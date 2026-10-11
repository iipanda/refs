import AppKit
import AVFoundation
import ScreenCaptureKit

/// Streams the selected content into an H.264 movie. All writer access uses one serial queue.
final class VideoRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("refs-\(UUID().uuidString).mp4")
    private let queue = DispatchQueue(label: "refs.video")
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var firstTime: CMTime?
    private var lastTime: CMTime?
    private var firstFrameDate: Date?
    private var failure: Error?
    var onFailure: ((Error) -> Void)?

    func start(frame: NSRect, windowID: CGWindowID?) async throws {
        let content = try await ScreenCapturer.shareableContent()
        let filter: SCContentFilter
        let config = SCStreamConfiguration()
        if let windowID {
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                throw CaptureError.windowGone
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            config.ignoreShadowsSingleWindow = true
            config.width = Int(window.frame.width * CGFloat(filter.pointPixelScale))
            config.height = Int(window.frame.height * CGFloat(filter.pointPixelScale))
        } else {
            let rect = ScreenGeometry.cgRect(fromCocoa: frame)
            guard let display = content.displays.max(by: {
                $0.frame.intersection(rect).width * $0.frame.intersection(rect).height <
                $1.frame.intersection(rect).width * $1.frame.intersection(rect).height
            }), display.frame.intersects(rect) else { throw CaptureError.noDisplay }
            filter = SCContentFilter(display: display,
                excludingApplications: content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier },
                exceptingWindows: [])
            let clipped = display.frame.intersection(rect)
            config.sourceRect = clipped.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
            config.width = Int(clipped.width * CGFloat(filter.pointPixelScale))
            config.height = Int(clipped.height * CGFloat(filter.pointPixelScale))
        }
        // H.264 needs even dimensions; cap the longest edge at 3840 for modest memory/encoder use.
        let ratio = min(1, 3840.0 / Double(max(config.width, config.height)))
        config.width = max(2, Int(Double(config.width) * ratio) / 2 * 2)
        config.height = max(2, Int(Double(config.height) * ratio) / 2 * 2)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.showsCursor = true
        config.capturesAudio = false
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: config.width, AVVideoHeightKey: config.height,
        ])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        self.writer = writer
        self.input = input
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        self.stream = stream
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        try queue.sync { if let failure { throw failure } }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sample.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue,
              let writer, let input, failure == nil else { return }
        let time = sample.presentationTimeStamp
        if firstTime == nil {
            guard writer.startWriting() else { fail(writer.error ?? CocoaError(.fileWriteUnknown)); return }
            writer.startSession(atSourceTime: time)
            firstTime = time
            firstFrameDate = Date()
        }
        guard input.isReadyForMoreMediaData else { return }
        if input.append(sample) { lastTime = time }
        else { fail(writer.error ?? CocoaError(.fileWriteUnknown)) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async { self.fail(error) }
    }

    private func fail(_ error: Error) {
        guard failure == nil else { return }
        failure = error
        DispatchQueue.main.async { self.onFailure?(error) }
    }

    func stop() async throws -> URL {
        try? await stream?.stopCapture()
        stream = nil
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard let writer = self.writer, let first = self.firstTime, let last = self.lastTime,
                      self.failure == nil else {
                    self.writer?.cancelWriting()
                    continuation.resume(throwing: self.failure ?? CaptureError.noVideoFrames)
                    return
                }
                // Include the final frame, even when the source is static and sends no new frames.
                let end = CMTimeAdd(first, CMTime(seconds: max(0.1, Date().timeIntervalSince(self.firstFrameDate ?? Date())), preferredTimescale: 600))
                writer.endSession(atSourceTime: CMTimeMaximum(CMTimeAdd(last, CMTime(value: 1, timescale: 30)), end))
                self.input?.markAsFinished()
                writer.finishWriting {
                    if writer.status == .completed { continuation.resume(returning: self.url) }
                    else { continuation.resume(throwing: writer.error ?? CocoaError(.fileWriteUnknown)) }
                }
            }
        }
    }

    func discardFile() { try? FileManager.default.removeItem(at: url) }
}
