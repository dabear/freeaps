import Combine
import LoopKitUI
import RileyLinkBLEKit

extension CGMConfig {
    final class Provider: BaseProvider, CGMConfigProvider {
        @Injected() var apsManager: APSManager!

        func setCGMManager(_ manager: CGMManagerUI) {
            apsManager.cgmManager = manager
        }

        var cgmDisplayState: AnyPublisher<CGMDisplayState?, Never> {
            apsManager.cgmDisplayState.eraseToAnyPublisher()
        }
    }
}
