import Combine
import Foundation

/// Effect mode for the virtual camera.
enum FreezeMode: String, Codable {
    case live          // pass the camera through
    case frozen        // hold the last frame, re-send every ~1s
    case loop          // play a video file on loop
    case badConnection // stutter: advance the picture ~2x per second
}

struct AppState: Codable {
    var mode: FreezeMode = .live
    var loopFile: String? = nil
}

/// Persists UI state to ~/Library/Application Support/OpenFreeze/state.json.
/// The frame pump polls the file so headless/scripted control stays in sync
/// with the SwiftUI toggles (and the last mode survives relaunch).
final class StateStore: ObservableObject {
    static let shared = StateStore()

    @Published var state = AppState()
    let fileURL: URL
    private var cancellables = Set<AnyCancellable>()

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenFreeze", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("state.json")
        reload()
        $state
            .dropFirst()
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)
    }

    func reload() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(AppState.self, from: data) {
            state = decoded
        }
    }

    func save() {
        try? JSONEncoder().encode(state).write(to: fileURL, options: .atomic)
    }

    /// Write state from outside the UI (scripts/tests). The pump picks it up on its next poll.
    static func writeExternal(mode: FreezeMode, loopFile: String? = nil) {
        let store = StateStore()
        store.state.mode = mode
        if let loopFile = loopFile { store.state.loopFile = loopFile }
        store.save()
    }
}
