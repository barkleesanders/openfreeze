import CoreMediaIO
import Foundation
import os.log

private let log = OSLog(subsystem: "com.openfreeze.OpenFreeze.cameraextension", category: "main")

autoreleasepool {
    let providerSource = ProviderSource()
    let provider = CMIOExtensionProvider(source: providerSource, clientQueue: nil)
    do {
        let deviceSource = DeviceSource()
        let device = CMIOExtensionDevice(localizedName: "OpenFreeze",
                                         deviceID: UUID(),
                                         legacyDeviceID: nil,
                                         source: deviceSource)
        try device.addStream(deviceSource.sourceStream)
        try device.addStream(deviceSource.sinkStream)
        try provider.addDevice(device)
        CMIOExtensionProvider.startService(provider: provider)
        os_log("OpenFreeze camera extension service started", log: log, type: .info)
    } catch {
        os_log("Failed to start extension: %{public}@", log: log, type: .fault, String(describing: error))
        exit(1)
    }
    RunLoop.main.run()
}
