import CoreMediaIO
import CoreMedia
import Foundation
import os.log

private let log = OSLog(subsystem: "com.openfreeze.OpenFreeze.cameraextension", category: "stream")

/// Stream-level source shared by the .source and .sink streams.
/// The .source stream forwards frames pulled from the .sink stream to consumers
/// (Zoom/Meet/Teams) via the Pump.
final class StreamSource: NSObject, CMIOExtensionStreamSource {

    enum Kind { case source, sink }

    let kind: Kind
    weak var pump: Pump?
    let formats: [CMIOExtensionStreamFormat]

    static let width: Int32 = 1280
    static let height: Int32 = 720
    static let frameRate: Int32 = 30

    init(kind: Kind) {
        self.kind = kind
        var desc: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault,
                                                    codecType: kCVPixelFormatType_32BGRA,
                                                    width: Self.width,
                                                    height: Self.height,
                                                    extensions: nil,
                                                    formatDescriptionOut: &desc)
        precondition(status == noErr && desc != nil, "Failed to create format description")
        let frameDuration = CMTime(value: 1, timescale: Self.frameRate)
        let format = CMIOExtensionStreamFormat(formatDescription: desc!,
                                               maxFrameDuration: frameDuration,
                                               minFrameDuration: frameDuration,
                                               validFrameDurations: nil)
        self.formats = [format]
        super.init()
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        var props: Set<CMIOExtensionProperty> = [.streamActiveFormatIndex, .streamFrameDuration]
        if kind == .sink {
            props.insert(.streamSinkBufferQueueSize)
        }
        return props
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let props = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) {
            props.activeFormatIndex = 0
        }
        if properties.contains(.streamFrameDuration) {
            props.frameDuration = CMTime(value: 1, timescale: Self.frameRate)
        }
        if kind == .sink, properties.contains(.streamSinkBufferQueueSize) {
            props.sinkBufferQueueSize = 8
        }
        return props
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
    }

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        true
    }

    func startStream() throws {
        if kind == .source {
            os_log("Source stream started — pump on", log: log, type: .info)
            pump?.start()
        }
    }

    func stopStream() throws {
        if kind == .source {
            os_log("Source stream stopped — pump off", log: log, type: .info)
            pump?.stop()
        }
    }
}

/// Moves sample buffers from the sink stream (fed by the OpenFreeze app)
/// to the source stream (consumed by video-call apps).
final class Pump {
    private let sourceStream: CMIOExtensionStream
    private let sinkStream: CMIOExtensionStream
    private let queue = DispatchQueue(label: "com.openfreeze.pump")
    private var running = false

    init(sourceStream: CMIOExtensionStream, sinkStream: CMIOExtensionStream) {
        self.sourceStream = sourceStream
        self.sinkStream = sinkStream
    }

    func start() {
        queue.sync {
            guard !running else { return }
            running = true
            queue.async { [weak self] in self?.poll() }
        }
    }

    func stop() {
        queue.sync { running = false }
    }

    private func poll() {
        guard running else { return }
        let group = DispatchGroup()
        for client in sinkStream.streamingClients {
            group.enter()
            drain(client: client) { group.leave() }
        }
        group.notify(queue: queue) { [weak self] in
            guard let self = self, self.running else { return }
            self.queue.asyncAfter(deadline: .now() + 0.005) { self.poll() }
        }
    }

    private func drain(client: CMIOExtensionClient, done: @escaping () -> Void) {
        sinkStream.consumeSampleBuffer(from: client) { [weak self] sampleBuffer, _, _, hasMore, _ in
            if let sampleBuffer = sampleBuffer, let self = self {
                let nowNs = UInt64(clock_gettime_nsec_np(CLOCK_UPTIME_RAW))
                self.sourceStream.send(sampleBuffer, discontinuity: [], hostTimeInNanoseconds: nowNs)
            }
            if hasMore {
                self?.drain(client: client, done: done)
            } else {
                done()
            }
        }
    }
}
