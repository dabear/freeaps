import Combine
import Foundation
import LibreTransmitter
import LibreTransmitterUI
import LoopKit
import LoopKitUI
import MinimedKit
import MockKit
import OmniKit
import SwiftDate
import Swinject
import UserNotifications

protocol DeviceDataManager {
    var pumpManager: PumpManagerUI? { get set }
    var cgmManager: CGMManagerUI? { get set }
    var pumpDisplayState: CurrentValueSubject<PumpDisplayState?, Never> { get }
    var cgmDisplayState: CurrentValueSubject<CGMDisplayState?, Never> { get }
    var pluginGlucose: CurrentValueSubject<[BloodGlucose], Never> { get }
    var recommendsLoop: PassthroughSubject<Void, Never> { get }
    var bolusTrigger: PassthroughSubject<Bool, Never> { get }
    var errorSubject: PassthroughSubject<Error, Never> { get }
    var pumpName: CurrentValueSubject<String, Never> { get }
    var cgmName: CurrentValueSubject<String, Never> { get }
    var pumpExpiresAtDate: CurrentValueSubject<Date?, Never> { get }
    func heartbeat(date: Date, force: Bool)
    func createBolusProgressReporter() -> DoseProgressReporter?
}

private let staticPumpManagers: [PumpManagerUI.Type] = [
    MinimedPumpManager.self,
    OmnipodPumpManager.self,
    MockPumpManager.self
]

private let staticCGMManagers: [CGMManagerUI.Type] = [
    LibreTransmitterManager.self
]

private let staticPumpManagersByIdentifier: [String: PumpManagerUI.Type] = staticPumpManagers.reduce(into: [:]) { map, Type in
    map[Type.managerIdentifier] = Type
}

private let staticCGMManagersByIdentifier: [String: CGMManagerUI.Type] = staticCGMManagers.reduce(into: [:]) { map, Type in
    map[Type.managerIdentifier] = Type
}

private let accessLock = NSRecursiveLock(label: "BaseDeviceDataManager.accessLock")

final class BaseDeviceDataManager: DeviceDataManager, Injectable {
    private let processQueue = DispatchQueue.markedQueue(label: "BaseDeviceDataManager.processQueue")
    @Injected() private var pumpHistoryStorage: PumpHistoryStorage!
    @Injected() private var storage: FileStorage!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var glucoseStorage: GlucoseStorage!

    @Injected() private var nightscout: NightscoutManager!

    @Persisted(key: "BaseDeviceDataManager.lastEventDate") var lastEventDate: Date? = nil
    @SyncAccess(lock: accessLock) @Persisted(key: "BaseDeviceDataManager.lastHeartBeatTime") var lastHeartBeatTime: Date =
        .distantPast

    let recommendsLoop = PassthroughSubject<Void, Never>()
    let bolusTrigger = PassthroughSubject<Bool, Never>()
    let errorSubject = PassthroughSubject<Error, Never>()
    let pumpNewStatus = PassthroughSubject<Void, Never>()
    let pluginGlucose = CurrentValueSubject<[BloodGlucose], Never>([])

    var cgmManager: CGMManagerUI? {
        didSet {
            cgmManager?.cgmManagerDelegate = self
            cgmManager?.delegateQueue = processQueue
            UserDefaults.standard.cgmManagerRawValue = cgmManager?.rawValue
            if let cgmManager = cgmManager {
                cgmDisplayState.value = CGMDisplayState(name: cgmManager.localizedTitle, image: cgmManager.smallImage)
                cgmName.send(cgmManager.localizedTitle)

            } else {
                cgmDisplayState.value = nil
            }
        }
    }

    var pumpManager: PumpManagerUI? {
        didSet {
            pumpManager?.pumpManagerDelegate = self
            pumpManager?.delegateQueue = processQueue
            UserDefaults.standard.pumpManagerRawValue = pumpManager?.rawValue
            if let pumpManager = pumpManager {
                pumpDisplayState.value = PumpDisplayState(name: pumpManager.localizedTitle, image: pumpManager.smallImage)
                pumpName.send(pumpManager.localizedTitle)

                if let omnipod = pumpManager as? OmnipodPumpManager {
                    guard let endTime = omnipod.state.podState?.expiresAt else {
                        pumpExpiresAtDate.send(nil)
                        return
                    }
                    pumpExpiresAtDate.send(endTime)
                }
            } else {
                pumpDisplayState.value = nil
            }
        }
    }

    var hasBLEHeartbeat: Bool {
        (pumpManager as? MockPumpManager) == nil
    }

    let cgmDisplayState = CurrentValueSubject<CGMDisplayState?, Never>(nil)
    let pumpDisplayState = CurrentValueSubject<PumpDisplayState?, Never>(nil)
    let pumpExpiresAtDate = CurrentValueSubject<Date?, Never>(nil)
    let pumpName = CurrentValueSubject<String, Never>("Pump")
    let cgmName = CurrentValueSubject<String, Never>("CGM")

    init(resolver: Resolver) {
        injectServices(resolver)
        setupPumpManager()
        setupCGMManager()
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    func setupCGMManager() {
        if let cgmManagerRawValue = UserDefaults.standard.cgmManagerRawValue {
            cgmManager = cgmManagerFromRawValue(cgmManagerRawValue)
        }
    }

    func setupPumpManager() {
        if let pumpManagerRawValue = UserDefaults.standard.pumpManagerRawValue {
            pumpManager = pumpManagerFromRawValue(pumpManagerRawValue)
        }
    }

    func createBolusProgressReporter() -> DoseProgressReporter? {
        pumpManager?.createBolusProgressReporter(reportingOn: processQueue)
    }

    func heartbeat(date: Date, force: Bool) {
        processQueue.safeSync {
            if force {
                updatePumpData()
                return
            }

            var updateInterval: TimeInterval = 4.5 * 60

            switch date.timeIntervalSince(lastHeartBeatTime) {
            case let interval where interval > 10.minutes.timeInterval:
                break
            case let interval where interval > 5.minutes.timeInterval:
                updateInterval = 1.minutes.timeInterval
            default:
                break
            }

            let interval = date.timeIntervalSince(lastHeartBeatTime)
            guard interval >= updateInterval else {
                debug(.deviceManager, "Last hearbeat \(interval / 60) min ago, skip updating the pump data")
                return
            }

            lastHeartBeatTime = date
            updatePumpData()
        }
    }

    private func updatePumpData() {
        guard let pumpManager = pumpManager else {
            debug(.deviceManager, "Pump is not set, skip updating")
            return
        }

        debug(.deviceManager, "Start updating the pump data")

        pumpManager.ensureCurrentPumpData {
            debug(.deviceManager, "Pump Data updated")
        }
    }

    private func pumpManagerFromRawValue(_ rawValue: [String: Any]) -> PumpManagerUI? {
        guard let rawState = rawValue["state"] as? PumpManager.RawStateValue,
              let Manager = pumpManagerTypeFromRawValue(rawValue)
        else {
            return nil
        }

        return Manager.init(rawState: rawState) as? PumpManagerUI
    }

    private func pumpManagerTypeFromRawValue(_ rawValue: [String: Any]) -> PumpManager.Type? {
        guard let managerIdentifier = rawValue["managerIdentifier"] as? String else {
            return nil
        }

        return staticPumpManagersByIdentifier[managerIdentifier]
    }

    private func cgmManagerFromRawValue(_ rawValue: [String: Any]) -> CGMManagerUI? {
        guard let rawState = rawValue["state"] as? CGMManager.RawStateValue,
              let Manager = cgmManagerTypeFromRawValue(rawValue)
        else {
            return nil
        }

        return Manager.init(rawState: rawState) as? CGMManagerUI
    }

    private func cgmManagerTypeFromRawValue(_ rawValue: [String: Any]) -> CGMManager.Type? {
        guard let managerIdentifier = rawValue["managerIdentifier"] as? String else {
            return nil
        }

        return staticCGMManagersByIdentifier[managerIdentifier]
    }
}

extension BaseDeviceDataManager: CGMManagerDelegate {
    func startDateToFilterNewData(for _: CGMManager) -> Date? {
        glucoseStorage.syncDate()
    }

    func cgmManagerWantsDeletion(_: CGMManager) {
        cgmManager = nil
    }

    func cgmManagerDidUpdateState(_ cgmManager: CGMManager) {
        debug(.deviceManager, "cgmmanager did update state")
        UserDefaults.standard.cgmManagerRawValue = cgmManager.rawValue
        if self.cgmManager == nil, let newCGMManager = cgmManager as? CGMManagerUI {
            self.cgmManager = newCGMManager
        }
        cgmName.send(cgmManager.localizedTitle)
    }

    func credentialStoragePrefix(for _: CGMManager) -> String {
        debug(.deviceManager, "credentialStoragePrefix called")
        return "no.bjorninge.libre"
    }

    private func trendToDirection(_ trend: LoopKit.GlucoseTrend?) -> BloodGlucose.Direction? {
        guard let trend = trend else {
            // return .notComputable
            return nil
        }

        /* TrendType:

         case upUpUp       = 1
         case upUp         = 2
         case up           = 3
         case flat         = 4
         case down         = 5
         case downDown     = 6
         case downDownDown = 7

         */
        /*
         Direction:
         enum Direction: String, JSON {
             case tripleUp = "TripleUp"
             case doubleUp = "DoubleUp"
             case singleUp = "SingleUp"
             case fortyFiveUp = "FortyFiveUp"
             case flat = "Flat"
             case fortyFiveDown = "FortyFiveDown"
             case singleDown = "SingleDown"
             case doubleDown = "DoubleDown"
             case tripleDown = "TripleDown"
             case none = "NONE"
             case notComputable = "NOT COMPUTABLE"
             case rateOutOfRange = "RATE OUT OF RANGE"
         }
         **/

        switch trend {
        case .upUpUp:
            return .tripleUp
        case .upUp:
            return .doubleUp
        case .up:
            return .singleUp
        case .flat:
            return .flat
        case .down:
            return .singleDown
        case .downDown:
            return .doubleDown
        case .downDownDown:
            return .tripleDown
        @unknown default:
            // return .notComputable
            return nil
        }
    }

    func cgmManager(_: CGMManager, hasNew readingResult: CGMReadingResult) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        debug(.deviceManager, "cgmManager received new value: \(readingResult)")
        guard case let .newData(glucoseSamples) = readingResult else {
            debug(.deviceManager, "No new glucose retrieved")
            return
        }

        // There is no guarantee that glucoseSamples are in cronological order,
        // so we need to sort them to be able to add trend to the last one
        let sortedSamples = glucoseSamples.sorted { $0.date > $1.date }
        let latest = sortedSamples.first

        var result = [BloodGlucose]()
        for sample in sortedSamples {
            let asMgdl = Int(sample.quantity.doubleValue(for: .milligramsPerDeciliter).rounded())

            result.append(BloodGlucose(
                _id: UUID().uuidString,
                device: "Freeaps",
                sgv: asMgdl,
                // TODO: get this from cgmmanager somehow for each reading
                // rather than once for the last sample
                direction: sample == latest ? trendToDirection(cgmManager?.glucoseDisplay?.trendType) : nil,
                date: Decimal(Int(sample.date.timeIntervalSince1970 * 1000)),
                dateString: sample.date,
                filtered: nil,
                noise: nil,
                glucose: asMgdl
            ))
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                debug(.deviceManager, "could not send glucose value")
                return
            }
            debug(.deviceManager, "pluginglucose, sending \(result.count) entries")
            self.pluginGlucose.send(result)
            if self.cgmManager?.shouldSyncToRemoteService == true {
                self.nightscout.uploadPrimarySourceGlucoseValues(result)
            }
        }
    }

    func cgmManager(_: CGMManager, didUpdate status: CGMManagerStatus) {
        debug(.deviceManager, "cgmManager received new status: \(status)")
    }
}

extension BaseDeviceDataManager: PumpManagerDelegate {
    func pumpManager(_: PumpManager, didAdjustPumpClockBy adjustment: TimeInterval) {
        debug(.deviceManager, "didAdjustPumpClockBy \(adjustment)")
    }

    func pumpManagerDidUpdateState(_ pumpManager: PumpManager) {
        UserDefaults.standard.pumpManagerRawValue = pumpManager.rawValue
        if self.pumpManager == nil, let newPumpManager = pumpManager as? PumpManagerUI {
            self.pumpManager = newPumpManager
        }
        pumpName.send(pumpManager.localizedTitle)
    }

    func pumpManagerBLEHeartbeatDidFire(_: PumpManager) {
        debug(.deviceManager, "Pump Heartbeat")
    }

    func pumpManagerMustProvideBLEHeartbeat(_: PumpManager) -> Bool {
        true
    }

    func pumpManager(_ pumpManager: PumpManager, didUpdate status: PumpManagerStatus, oldStatus _: PumpManagerStatus) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        debug(.deviceManager, "New pump status Bolus: \(status.bolusState)")
        debug(.deviceManager, "New pump status Basal: \(String(describing: status.basalDeliveryState))")

        if case .inProgress = status.bolusState {
            bolusTrigger.send(true)
        } else {
            bolusTrigger.send(false)
        }

        let batteryPercent = Int((status.pumpBatteryChargeRemaining ?? 1) * 100)
        let battery = Battery(
            percent: batteryPercent,
            voltage: nil,
            string: batteryPercent >= 10 ? .normal : .low,
            display: pumpManager.status.pumpBatteryChargeRemaining != nil
        )
        storage.save(battery, as: OpenAPS.Monitor.battery)
        broadcaster.notify(PumpBatteryObserver.self, on: processQueue) {
            $0.pumpBatteryDidChange(battery)
        }

        if let omnipod = pumpManager as? OmnipodPumpManager {
            let reservoir = omnipod.state.podState?.lastInsulinMeasurements?.reservoirLevel ?? 0xDEAD_BEEF

            storage.save(Decimal(reservoir), as: OpenAPS.Monitor.reservoir)
            broadcaster.notify(PumpReservoirObserver.self, on: processQueue) {
                $0.pumpReservoirDidChange(Decimal(reservoir))
            }

            guard let endTime = omnipod.state.podState?.expiresAt else {
                pumpExpiresAtDate.send(nil)
                return
            }
            pumpExpiresAtDate.send(endTime)
        }
    }

    func pumpManagerWillDeactivate(_: PumpManager) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        pumpManager = nil
    }

    func pumpManager(_: PumpManager, didUpdatePumpRecordsBasalProfileStartEvents _: Bool) {}

    func pumpManager(_: PumpManager, didError error: PumpManagerError) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        debug(.deviceManager, "error: \(error.localizedDescription), reason: \(String(describing: error.failureReason))")
        errorSubject.send(error)
    }

    func pumpManager(
        _: PumpManager,
        hasNewPumpEvents events: [NewPumpEvent],
        lastReconciliation _: Date?,
        completion: @escaping (_ error: Error?) -> Void
    ) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        debug(.deviceManager, "New pump events:\n\(events.map(\.title).joined(separator: "\n"))")
        pumpHistoryStorage.storePumpEvents(events)
        lastEventDate = events.last?.date
        completion(nil)
    }

    func pumpManager(
        _: PumpManager,
        didReadReservoirValue units: Double,
        at date: Date,
        completion: @escaping (Result<
            (newValue: ReservoirValue, lastValue: ReservoirValue?, areStoredValuesContinuous: Bool),
            Error
        >) -> Void
    ) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        debug(.deviceManager, "Reservoir Value \(units), at: \(date)")
        storage.save(Decimal(units), as: OpenAPS.Monitor.reservoir)
        broadcaster.notify(PumpReservoirObserver.self, on: processQueue) {
            $0.pumpReservoirDidChange(Decimal(units))
        }

        completion(.success((
            newValue: Reservoir(startDate: Date(), unitVolume: units),
            lastValue: nil,
            areStoredValuesContinuous: true
        )))
    }

    func pumpManagerRecommendsLoop(_: PumpManager) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        debug(.deviceManager, "Recomends loop")
        recommendsLoop.send()
    }

    func startDateToFilterNewPumpEvents(for _: PumpManager) -> Date {
        lastEventDate?.addingTimeInterval(-15.minutes.timeInterval) ?? Date().addingTimeInterval(-2.hours.timeInterval)
    }
}

// MARK: - DeviceManagerDelegate

extension BaseDeviceDataManager: DeviceManagerDelegate {
    func scheduleNotification(
        for _: DeviceManager,
        identifier: String,
        content: UNNotificationContent,
        trigger: UNNotificationTrigger?
    ) {
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        DispatchQueue.main.async {
            UNUserNotificationCenter.current().add(request)
        }
    }

    func clearNotification(for _: DeviceManager, identifier: String) {
        DispatchQueue.main.async {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
        }
    }

    func removeNotificationRequests(for _: DeviceManager, identifiers: [String]) {
        DispatchQueue.main.async {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    func deviceManager(
        _: DeviceManager,
        logEventForDeviceIdentifier _: String?,
        type _: DeviceLogEntryType,
        message: String,
        completion _: ((Error?) -> Void)?
    ) {
        debug(.deviceManager, "Device message: \(message)")
    }
}

// MARK: - AlertPresenter

extension BaseDeviceDataManager: AlertPresenter {
    func issueAlert(_: Alert) {}
    func retractAlert(identifier _: Alert.Identifier) {}
}

// MARK: Others

protocol PumpReservoirObserver {
    func pumpReservoirDidChange(_ reservoir: Decimal)
}

protocol PumpBatteryObserver {
    func pumpBatteryDidChange(_ battery: Battery)
}
