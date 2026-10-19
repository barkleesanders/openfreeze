import CoreMediaIO
import Foundation

/// Provider-level source: accepts clients and reports the provider manufacturer.
/// Devices are attached imperatively via `provider.addDevice(_:)` in main.swift.
final class ProviderSource: NSObject, CMIOExtensionProviderSource {

    func connect(to client: CMIOExtensionClient) throws {
        // Accept every client.
    }

    func disconnect(from client: CMIOExtensionClient) {
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.providerManufacturer]
    }

    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        let props = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerManufacturer) {
            props.manufacturer = "OpenFreeze"
        }
        return props
    }

    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {
    }
}
