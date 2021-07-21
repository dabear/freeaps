import Combine
import LoopKit
import LoopKitUI

enum CGMConfig {
    enum Config {}

    enum CGMType: Equatable {
        case libretransmitter
    }

    struct CGMInitialSettings {
        let foo: Double

        static let `default` = CGMInitialSettings(foo: 2)
    }
}

struct CGMDisplayState {
    let name: String
    let image: UIImage?
}

protocol CGMConfigProvider: Provider {
    func setCGMManager(_: CGMManagerUI)
    var cgmDisplayState: AnyPublisher<CGMDisplayState?, Never> { get }
}
