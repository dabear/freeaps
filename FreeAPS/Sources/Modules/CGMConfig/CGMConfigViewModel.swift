import LoopKit
import LoopKitUI
import SwiftDate
import SwiftUI

extension CGMConfig {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: CGMConfigProvider {
        @Published var setupCGM = false
        private(set) var setupCGMType: CGMType = .libretransmitter
        @Published var cgmState: CGMDisplayState?
        private(set) var initialSettings: CGMInitialSettings = .default

        override func subscribe() {
            provider.cgmDisplayState
                .receive(on: DispatchQueue.main)
                .assign(to: \.cgmState, on: self)
                .store(in: &lifetime)

            initialSettings = CGMInitialSettings(foo: 2)
        }

        func addCGM(_ type: CGMType) {
            setupCGM = true
            setupCGMType = type
        }
    }
}

extension CGMConfig.ViewModel: CompletionDelegate {
    func completionNotifyingDidComplete(_: CompletionNotifying) {
        print("CGMConfig.ViewModel: CompletionDelegate")
        setupCGM = false
    }
}

extension CGMConfig.ViewModel: CGMManagerSetupViewControllerDelegate {
    func cgmManagerSetupViewController(_: CGMManagerSetupViewController, didSetUpCGMManager cgmManager: CGMManagerUI) {
        provider.setCGMManager(cgmManager)
        setupCGM = false
    }
}
