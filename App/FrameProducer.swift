import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation

/// Produces 1280x720 BGRA frames from the physical webcam when one exists,
/// otherwise from a built-in synthetic test pattern (moving bar + frame counter).
/// Applies the selected FreezeMode and hands CMSampleBuffers to the SinkPump.
final class FrameProducer: NSObject {

    static let width = 1280
    static let height = 720

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.openfreeze.capture")
    private let lock = NSLock()
    private var _latest: CMSampleBuffer?
    private var latest: CMSampleBuffer? {
        get { lock.lock(); defer { lock.unlock() }; return _latest }
        set { lock.lock(); defer { lock.unlock() }; _latest = newValue }
    }

    private var usingCamera = false
    private var synthTimer: DispatchSourceTimer?
    private var synthFrame = 0
    private var synthPool: CVPixelBufferPool?
    private var formatDesc: CMFormatDescription?

    private var frozenBuffer: CMSampleBuffer?
    private var heldBuffer: CMSampleBuffer?
    private var badTick = 0
    private var loopReader: AVAssetReader?
    private var loopOutput: AVAssetReaderTrackOutput?
    private var loopURL: URL?
    private var ptsCounter: Int64 = 0

    var previewLayer: AVCaptureVideoPreviewLayer?

    override init() {
        super.init()
        var desc: CMFormatDescription?
        CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault,
                                       codecType: kCVPixelFormatType_32BGRA,
                                       width: Int32(Self.width), height: Int32(Self.height),
                                       extensions: nil, formatDescriptionOut: &desc)
        formatDesc = desc
        startSource()
    }

    // MARK: - Source

    private func startSource() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            var deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
            if #available(macOS 14.0, *) { deviceTypes.append(.external) }
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: deviceTypes,
                mediaType: .video, position: .unspecified)
            if let camera = discovery.devices.first,
               let input = try? AVCaptureDeviceInput(device: camera) {
                self.session.beginConfiguration()
                if self.session.canAddInput(input) { self.session.addInput(input) }
                let output = AVCaptureVideoDataOutput()
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                output.setSampleBufferDelegate(self, queue: self.sessionQueue)
                if self.session.canAddOutput(output) { self.session.addOutput(output) }
                self.session.commitConfiguration()
                self.session.startRunning()
                self.usingCamera = true
                DispatchQueue.main.async {
                    let layer = AVCaptureVideoPreviewLayer(session: self.session)
                    layer.videoGravity = .resizeAspect
                    self.previewLayer = layer
                }
            } else {
                self.startSynthetic()
            }
        }
    }

    var isUsingCamera: Bool { usingCamera }

    // MARK: - Synthetic test pattern (no physical camera, e.g. Mac mini)

    private func startSynthetic() {
        var pool: CVPixelBufferPool?
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Self.width,
            kCVPixelBufferHeightKey as String: Self.height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &pool)
        synthPool = pool
        let timer = DispatchSource.makeTimerSource(queue: sessionQueue)
        timer.schedule(deadline: .now(), repeating: 1.0 / 30.0)
        timer.setEventHandler { [weak self] in self?.renderSyntheticFrame() }
        timer.resume()
        synthTimer = timer
    }

    private func renderSyntheticFrame() {
        guard let pool = synthPool, let formatDesc = formatDesc else { return }
        var pb: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pb) == kCVReturnSuccess,
              let pixelBuffer = pb else { return }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let w = Self.width, h = Self.height
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let ctx = CGContext(data: base, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: bytesPerRow,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        ctx?.setFillColor(CGColor(red: 0.08, green: 0.10, blue: 0.16, alpha: 1))
        ctx?.fill(CGRect(x: 0, y: 0, width: w, height: h))
        // Moving bar proves frames are live.
        let barX = (synthFrame * 17) % (w - 120)
        ctx?.setFillColor(CGColor(red: 0.2, green: 0.8, blue: 0.4, alpha: 1))
        ctx?.fill(CGRect(x: barX, y: h / 2 - 40, width: 120, height: 80))
        // Frame counter text.
        let text = "OPENFREEZE TEST  frame \(synthFrame)" as NSString
        ctx?.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        text.draw(at: CGPoint(x: 40, y: 60), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 36, weight: .bold)])
        synthFrame += 1
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30),
                                        presentationTimeStamp: CMTime(value: Int64(synthFrame), timescale: 30),
                                        decodeTimeStamp: .invalid)
        var sbuf: CMSampleBuffer?
        if CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
                                              dataReady: true, makeDataReadyCallback: nil, refcon: nil,
                                              formatDescription: formatDesc, sampleTiming: &timing,
                                              sampleBufferOut: &sbuf) == noErr, let sbuf = sbuf {
            latest = sbuf
        }
    }

    // MARK: - Mode application

    /// Returns the next buffer to enqueue, or nil when the pump should wait.
    /// The pump calls this at ~30Hz; frozen mode is additionally gated to ~1Hz by the pump.
    func nextBuffer(mode: FreezeMode) -> CMSampleBuffer? {
        switch mode {
        case .live:
            frozenBuffer = nil
            return latest
        case .frozen:
            if frozenBuffer == nil { frozenBuffer = latest }
            guard let fb = frozenBuffer else { return nil }
            return retimed(fb)
        case .badConnection:
            badTick += 1
            if badTick % 15 == 1 || heldBuffer == nil { heldBuffer = latest }
            guard let hb = heldBuffer else { return nil }
            return retimed(hb)
        case .loop:
            return nextLoopBuffer() ?? latest
        }
    }

    func resetLoop() {
        loopReader = nil
        loopOutput = nil
    }

    private func openLoopAsset() -> Bool {
        guard let path = StateStore.shared.state.loopFile, !path.isEmpty else { return false }
        let url = URL(fileURLWithPath: path)
        guard loopURL != url || loopReader == nil else { return true }
        loopURL = url
        guard let reader = try? AVAssetReader(asset: AVURLAsset(url: url)),
              let track = AVURLAsset(url: url).tracks(withMediaType: .video).first else { return false }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        reader.add(output)
        reader.startReading()
        loopReader = reader
        loopOutput = output
        return true
    }

    private func nextLoopBuffer() -> CMSampleBuffer? {
        guard openLoopAsset(), let output = loopOutput else { return nil }
        if let sbuf = output.copyNextSampleBuffer() {
            return retimed(sbuf)
        }
        // End of file — reopen and loop.
        loopReader = nil
        loopOutput = nil
        guard openLoopAsset(), let output2 = loopOutput,
              let sbuf = output2.copyNextSampleBuffer() else { return nil }
        return retimed(sbuf)
    }

    /// Copy with a fresh monotonic presentation timestamp so each enqueue looks live.
    private func retimed(_ sbuf: CMSampleBuffer) -> CMSampleBuffer? {
        ptsCounter += 1
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30),
                                        presentationTimeStamp: CMTime(value: ptsCounter, timescale: 30),
                                        decodeTimeStamp: .invalid)
        var out: CMSampleBuffer?
        guard CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault,
                                                    sampleBuffer: sbuf,
                                                    sampleTimingEntryCount: 1,
                                                    sampleTimingArray: &timing,
                                                    sampleBufferOut: &out) == noErr else { return nil }
        return out
    }
}

extension FrameProducer: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        latest = sampleBuffer
    }
}
