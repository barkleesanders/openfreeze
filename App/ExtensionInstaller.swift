import Foundation
import SystemExtensions

/// Installs / activates the OpenFreeze camera system extension.
/// First run needs one approval in System Settings -> General -> Login Items & Extensions.
final class ExtensionInstaller: NSObject, ObservableObject, OSSystemExtensionRequestDelegate {

    static let extensionIdentifier = "com.openfreeze.OpenFreeze.cameraextension"

    @Published var status: String = "Not installed"

    func installOrActivate() {
        status = "Requesting…"
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: Self.extensionIdentifier, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    func uninstall() {
        status = "Requesting uninstall…"
        let request = OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: Self.extensionIdentifier, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    // MARK: OSSystemExtensionRequestDelegate

    func request(_ request: OSSystemExtensionRequest,
                 actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        status = "Needs approval: System Settings → General → Login Items & Extensions → Allow “OpenFreeze”"
    }

    func request(_ request: OSSystemExtensionRequest,
                 didFinishWithResult result: OSSystemExtensionRequest.Result) {
        switch result {
        case .completed: status = "Active ✓"
        case .willCompleteAfterReboot: status = "Will complete after reboot"
        @unknown default: status = "Finished: \(result.rawValue)"
        }
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        status = "Failed: \(error.localizedDescription)"
    }
}
