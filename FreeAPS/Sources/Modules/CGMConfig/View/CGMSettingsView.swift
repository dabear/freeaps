import LoopKitUI
import SwiftUI
import UIKit

extension CGMConfig {
    struct CGMSettingsView: UIViewControllerRepresentable {
        let cgmManager: CGMManagerUI
        weak var completionDelegate: CompletionDelegate?

        func makeUIViewController(context _: UIViewControllerRepresentableContext<CGMSettingsView>) -> UIViewController {
            var vc = cgmManager.settingsViewController(
                for: .millimolesPerLiter,
                glucoseTintColor: Color.red,
                guidanceColors: .init()
            )
            vc.completionDelegate = completionDelegate
            return vc
        }

        func updateUIViewController(_: UIViewController, context _: UIViewControllerRepresentableContext<CGMSettingsView>) {}
    }
}
