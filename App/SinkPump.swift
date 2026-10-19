import CoreMedia
import CoreMediaIO
import Foundation
import os.log

private let log = OSLog(subsystem: "com.openfreeze.OpenFreeze", category: "sinkpump")

/// Finds the OpenFreeze camera extension's sink stream through the classic
/// CoreMediaIO object model and enqueues CMSampleBuffers from the FrameProducer.
/// Mirrors the public client-side injection pattern: discover device by name,
/// start the sink stream, grab its CMSimpleQueue, keep it fed.
final class SinkPump {

    private let producer: FrameProducer
    private let pumpQueue = DispatchQueue(label: "com.openfreeze.sinkpump")
    private var timer: DispatchSourceTimer?
    private var deviceID: CMIODeviceID = 0
    private var streamID: CMIOStreamID = 0
    private var bufferQueue: CMSimpleQueue?
    /// Strong refs to recently enqueued buffers: CMSimpleQueue does not retain.
    private var liveBuffers: [CMSampleBuffer] = []
    private var lastFreezePush = Date.distantPast
    private var lastStatePoll = Date.distantPast
    private var cachedMode: FreezeMode = .live

    init(producer: FrameProducer) {
        self.producer = producer
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: pumpQueue)
        timer.schedule(deadline: .now() + 2.0, repeating: 1.0 / 30.0)
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    private func propAddr(_ selector: Int) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(selector),
                                  mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                  mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    private func tick() {
        // Re-read persisted state ~2x/sec so scripted/headless control stays in sync.
        if Date().timeIntervalSince(lastStatePoll) > 0.5 {
            lastStatePoll = Date()
            StateStore.shared.reload()
            let mode = StateStore.shared.state.mode
            if mode != cachedMode {
                cachedMode = mode
                if mode == .loop { producer.resetLoop() }
                os_log("Mode -> %{public}@", log: log, type: .info, String(describing: mode))
            }
        }
        guard bufferQueue != nil || connect() else { return }
        guard let queue = bufferQueue else { return }
        let mode = cachedMode
        // Frozen mode: re-push the held frame ~1x/sec (keeps the call alive on a still image).
        if mode == .frozen, Date().timeIntervalSince(lastFreezePush) < 1.0 { return }
        guard CMSimpleQueueGetCount(queue) < 4 else { return }
        guard let buffer = producer.nextBuffer(mode: mode) else { return }
        let token = Unmanaged.passUnretained(buffer).toOpaque()
        let status = CMSimpleQueueEnqueue(queue, element: token)
        if status == noErr {
            liveBuffers.append(buffer)
            if liveBuffers.count > 16 { liveBuffers.removeFirst(liveBuffers.count - 16) }
            if mode == .frozen { lastFreezePush = Date() }
        } else {
            os_log("Enqueue failed: %{public}d", log: log, type: .error, status)
        }
    }

    // MARK: - Discovery & connection

    private func objectName(_ objectID: CMIOObjectID) -> String? {
        var addr = propAddr(kCMIOObjectPropertyName)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(objectID, &addr, 0, nil, &size) == noErr else { return nil }
        var name: CFString = "" as CFString
        var used = size
        guard CMIOObjectGetPropertyData(objectID, &addr, 0, nil, size, &used, &name) == noErr else { return nil }
        return name as String
    }

    private func connect() -> Bool {
        guard let (device, stream) = findSink() else { return false }
        let startStatus = CMIODeviceStartStream(device, stream)
        guard startStatus == noErr else {
            os_log("CMIODeviceStartStream failed: %{public}d", log: log, type: .error, startStatus)
            return false
        }
        var unmanaged: Unmanaged<CMSimpleQueue>?
        let qStatus = CMIOStreamCopyBufferQueue(stream, nil, nil, &unmanaged)
        guard qStatus == noErr, let queue = unmanaged?.takeRetainedValue() else {
            os_log("CMIOStreamCopyBufferQueue failed: %{public}d", log: log, type: .error, qStatus)
            return false
        }
        deviceID = device
        streamID = stream
        bufferQueue = queue
        os_log("Connected to OpenFreeze sink stream", log: log, type: .info)
        return true
    }

    private func findSink() -> (CMIODeviceID, CMIOStreamID)? {
        var addr = propAddr(kCMIOHardwarePropertyDevices)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, &size) == noErr,
              size > 0 else { return nil }
        let count = Int(size) / MemoryLayout<CMIODeviceID>.size
        var devices = [CMIODeviceID](repeating: 0, count: count)
        var used = size
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, size, &used, &devices) == noErr else { return nil }
        for device in devices where objectName(device) == "OpenFreeze" {
            var saddr = propAddr(kCMIODevicePropertyStreams)
            var ssize: UInt32 = 0
            guard CMIOObjectGetPropertyDataSize(device, &saddr, 0, nil, &ssize) == noErr, ssize > 0 else { continue }
            let n = Int(ssize) / MemoryLayout<CMIOStreamID>.size
            var streams = [CMIOStreamID](repeating: 0, count: n)
            var sused = ssize
            guard CMIOObjectGetPropertyData(device, &saddr, 0, nil, ssize, &sused, &streams) == noErr else { continue }
            for stream in streams where objectName(stream) == "OpenFreeze Video Sink" {
                return (device, stream)
            }
        }
        return nil
    }
}
