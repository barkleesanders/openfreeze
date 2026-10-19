import CoreMediaIO
import Foundation

/// Device-level source. Owns the two streams:
///  - "OpenFreeze Video"      (.source) — what Zoom/Meet/Teams see
///  - "OpenFreeze Video Sink" (.sink)   — where the OpenFreeze app pushes frames
final class DeviceSource: NSObject, CMIOExtensionDeviceSource {

    private let sourceStreamSource = StreamSource(kind: .source)
    private let sinkStreamSource = StreamSource(kind: .sink)
    private(set) var sourceStream: CMIOExtensionStream!
    private(set) var sinkStream: CMIOExtensionStream!
    private let pump: Pump

    override init() {
        // Build streams first (super.init not yet called is fine: no self use before).
        let srcSrc = sourceStreamSource
        let sinkSrc = sinkStreamSource
        let src = CMIOExtensionStream(localizedName: "OpenFreeze Video",
                                      streamID: UUID(),
                                      direction: .source,
                                      clockType: .hostTime,
                                      source: srcSrc)
        let sink = CMIOExtensionStream(localizedName: "OpenFreeze Video Sink",
                                       streamID: UUID(),
                                       direction: .sink,
                                       clockType: .hostTime,
                                       source: sinkSrc)
        self.sourceStream = src
        self.sinkStream = sink
        self.pump = Pump(sourceStream: src, sinkStream: sink)
        super.init()
        srcSrc.pump = pump
        sinkSrc.pump = pump
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        []
    }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        CMIOExtensionDeviceProperties(dictionary: [:])
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {
    }
}
