import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var store: StateStore
    @ObservedObject var installer: ExtensionInstaller
    var producer: FrameProducer

    @State private var showPicker = false

    var body: some View {
        VStack(spacing: 16) {
            Text("OpenFreeze").font(.largeTitle).bold()
            Text("Free & open-source virtual camera for macOS")
                .foregroundColor(.secondary)

            PreviewView(producer: producer)
                .frame(width: 480, height: 270)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.4)))

            modeButtons

            if store.state.mode == .loop {
                HStack {
                    Text(store.state.loopFile.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "No video selected")
                        .foregroundColor(.secondary).lineLimit(1)
                    Button("Choose Video…") { showPicker = true }
                }
                .fileImporter(isPresented: $showPicker,
                              allowedContentTypes: [.movie],
                              onCompletion: { result in
                    if case .success(let url) = result {
                        store.state.loopFile = url.path
                        producer.resetLoop()
                    }
                })
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Camera extension").font(.headline)
                Text(installer.status).foregroundColor(.secondary)
                HStack {
                    Button("Install / Activate") { installer.installOrActivate() }
                    Button("Uninstall") { installer.uninstall() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(producer.isUsingCamera
                 ? "Source: built-in camera"
                 : "Source: synthetic test pattern (no camera found)")
                .font(.caption).foregroundColor(.secondary)
        }
        .padding(24)
        .frame(width: 560)
    }

    private var modeButtons: some View {
        HStack(spacing: 12) {
            ModeButton(title: "Go Live", active: store.state.mode == .live) {
                store.state.mode = .live
            }
            ModeButton(title: store.state.mode == .frozen ? "Unfreeze" : "Freeze",
                       active: store.state.mode == .frozen) {
                store.state.mode = (store.state.mode == .frozen) ? .live : .frozen
            }
            ModeButton(title: "Loop Video", active: store.state.mode == .loop) {
                if store.state.loopFile == nil { showPicker = true }
                store.state.mode = .loop
            }
            ModeButton(title: "Bad Connection", active: store.state.mode == .badConnection) {
                store.state.mode = (store.state.mode == .badConnection) ? .live : .badConnection
            }
        }
    }
}

struct ModeButton: View {
    let title: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .tint(active ? .green : .accentColor)
    }
}

struct PreviewView: NSViewRepresentable {
    var producer: FrameProducer

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        if let layer = producer.previewLayer {
            layer.frame = view.bounds
            layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            view.layer = layer
            view.wantsLayer = true
        } else {
            let label = NSTextField(labelWithString: "Synthetic test pattern — no camera on this Mac")
            label.alignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            ])
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
