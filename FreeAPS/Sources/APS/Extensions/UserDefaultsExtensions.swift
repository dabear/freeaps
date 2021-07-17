import Foundation
import LoopKit
import RileyLinkBLEKit
import RileyLinkKit

extension UserDefaults {
    private enum Key: String {
        case pumpManagerRawValue = "com.rileylink.PumpManagerRawValue"
        case cgmManagerRawValue = "com.rileylink.CGMManagerRawValue"
        case rileyLinkConnectionManagerState = "com.rileylink.RileyLinkConnectionManagerState"
    }

    var pumpManagerRawValue: PumpManager.RawStateValue? {
        get {
            dictionary(forKey: Key.pumpManagerRawValue.rawValue)
        }
        set {
            set(newValue, forKey: Key.pumpManagerRawValue.rawValue)
        }
    }

    var cgmManagerRawValue: CGMManager.RawStateValue? {
        get {
            dictionary(forKey: Key.cgmManagerRawValue.rawValue)
        }
        set {
            set(newValue, forKey: Key.cgmManagerRawValue.rawValue)
        }
    }

    var rileyLinkConnectionManagerState: RileyLinkConnectionManagerState? {
        get {
            guard let rawValue = dictionary(forKey: Key.rileyLinkConnectionManagerState.rawValue)
            else {
                return nil
            }
            return RileyLinkConnectionManagerState(rawValue: rawValue)
        }
        set {
            set(newValue?.rawValue, forKey: Key.rileyLinkConnectionManagerState.rawValue)
        }
    }
}
