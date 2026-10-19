import SwiftUI

@main
struct OpenFreezeApp: App {
    @StateObject private var store = StateStore.shared
    @StateObject private var installer = ExtensionInstaller()
    private let producer: FrameProducer
    private let pump: SinkPump
    private static var headlessInstaller: ExtensionInstaller?

    init() {
        let producer = FrameProducer()
        self.producer = producer
        self.pump = SinkPump(producer: producer)
        pump.start()
        // Headless/scripted activation (also useful for MDM fleets):
        // /Applications/OpenFreeze.app/Contents/MacOS/OpenFreeze --activate-extension
        if CommandLine.arguments.contains("--activate-extension") {
            Self.headlessInstaller = ExtensionInstaller()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                Self.headlessInstaller?.installOrActivate()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store, installer: installer, producer: producer)
        }
    }
}
