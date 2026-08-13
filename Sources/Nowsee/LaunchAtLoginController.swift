import Foundation
import ServiceManagement

@MainActor
@Observable
final class LaunchAtLoginController {
    static let shared = LaunchAtLoginController()

    private(set) var status: SMAppService.Status
    private(set) var isEnabled: Bool
    private(set) var isUpdating = false
    private(set) var errorMessage: String?

    var needsApproval: Bool { status == .requiresApproval }

    private init() {
        let initialStatus = SMAppService.mainApp.status
        status = initialStatus
        isEnabled = initialStatus == .enabled
    }

    func refresh() {
        status = SMAppService.mainApp.status
        isEnabled = status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        guard !isUpdating else { return }
        isUpdating = true
        isEnabled = enabled
        errorMessage = nil

        Task {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try await SMAppService.mainApp.unregister()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            refresh()
            isUpdating = false
        }
    }
}
