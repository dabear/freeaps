import LibreTransmitter
import LibreTransmitterUI
import LoopKit
import LoopKitUI
import SwiftUI
import UIKit

extension CGMConfig {
    struct CGMSetupView: UIViewControllerRepresentable {
        let cgmType: CGMType
        let cgmInitialSettings: CGMInitialSettings
        weak var completionDelegate: CompletionDelegate?
        weak var setupDelegate: CGMManagerSetupViewControllerDelegate?

        func makeUIViewController(context _: UIViewControllerRepresentableContext<CGMSetupView>) -> UIViewController {
            var setupViewController: CGMManagerSetupViewController & UIViewController & CompletionNotifying

            switch cgmType {
            case .libretransmitter:
                setupViewController = LibreTransmitterManager.setupViewController(
                    glucoseTintColor: .red,
                    guidanceColors: .init()
                )!
            }

            // TODO: replace with libre

            setupViewController.setupDelegate = setupDelegate
            setupViewController.completionDelegate = completionDelegate
            return setupViewController
        }

        func updateUIViewController(_: UIViewController, context _: UIViewControllerRepresentableContext<CGMSetupView>) {}
    }
}
