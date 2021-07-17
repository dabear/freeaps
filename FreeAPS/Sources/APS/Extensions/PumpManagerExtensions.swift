import LoopKit
import LoopKitUI

extension PumpManager {
    var rawValue: [String: Any] {
        [
            "managerIdentifier": type(of: self).managerIdentifier,
            "state": rawState
        ]
    }
}

extension CGMManager {
    var rawValue: [String: Any] {
        [
            "managerIdentifier": type(of: self).managerIdentifier,
            "state": rawState
        ]
    }
}

extension PumpManagerUI {
    static func setupViewController() -> PumpManagerSetupViewController & UIViewController & CompletionNotifying {
        setupViewController(
            insulinTintColor: .accentColor,
            guidanceColors: GuidanceColors(acceptable: .green, warning: .orange, critical: .red),
            allowedInsulinTypes: [.apidra, .humalog, .novolog, .fiasp]
        )
    }

    func settingsViewController() -> UIViewController & CompletionNotifying {
        settingsViewController(
            insulinTintColor: .accentColor,
            guidanceColors: GuidanceColors(acceptable: .green, warning: .orange, critical: .red),
            allowedInsulinTypes: [.apidra, .humalog, .novolog, .fiasp]
        )
    }
}

protocol PumpSettingsBuilder {
    func settingsViewController() -> UIViewController & CompletionNotifying
}
