import ClipGumCore
import Combine
import Foundation

@MainActor
final class EnterprisePolicyController: ObservableObject {
    let center: PolicyCenter
    @Published private(set) var snapshot: EnterprisePolicy

    init(center: PolicyCenter = PolicyCenter()) {
        self.center = center
        snapshot = center.snapshot()
    }

    func refresh() {
        let latest = center.snapshot()
        if latest != snapshot { snapshot = latest }
    }

    var badges: [String] { snapshot.lockedLabels }

    var scriptsAllowed: Bool { !snapshot.disableCustomScripts }
    var telemetryLocked: Bool { snapshot.lockTelemetry }

    /// Reads the managed domain again at the explicit write boundary rather
    /// than relying on a potentially stale settings-screen snapshot.
    var requiresRedactionNow: Bool { center.snapshot().forceSecretRedaction }
}
