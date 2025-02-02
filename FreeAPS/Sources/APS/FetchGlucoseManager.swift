import Combine
import Foundation
import SwiftDate
import Swinject

protocol FetchGlucoseManager {}

final class BaseFetchGlucoseManager: FetchGlucoseManager, Injectable {
    private let processQueue = DispatchQueue(label: "BaseGlucoseManager.processQueue")
    @Injected() var glucoseStorage: GlucoseStorage!
    @Injected() var nightscoutManager: NightscoutManager!
    @Injected() var apsManager: APSManager!

    private var lifetime = Lifetime()
    private let timer = DispatchTimer(timeInterval: 1.minutes.timeInterval)

    init(resolver: Resolver) {
        injectServices(resolver)
        subscribe()
        subscribeToCGMManager()
    }

    private var managerGlucose: [BloodGlucose]?
    func subscribeToCGMManager() {
        apsManager.cgmGlucoseValue.eraseToAnyPublisher()
            .sink { glucose in
                self.managerGlucose = glucose
            }
            .store(in: &lifetime)
    }

    // fetchFromCGMManagerOld did not ever complete, resulting in many "new glucose found"
    // so we hack it by using a Just([]) publisher instead
    private func fetchFromCGMManager() -> AnyPublisher<[BloodGlucose], Never> {
        if let glucose = managerGlucose {
            managerGlucose = []
            return Just(glucose).eraseToAnyPublisher()
        }
        return Just([]).eraseToAnyPublisher()
    }

    /* private func fetchFromCGMManagerOld() -> AnyPublisher<[BloodGlucose], Never> {
         apsManager.cgmGlucoseValue.eraseToAnyPublisher()
     } */

    var glucoseCombination:
        Publishers.CombineLatest<
            AnyPublisher<[BloodGlucose], Never>,
            AnyPublisher<[BloodGlucose], Never>
        > {
            let hasDirectSource = (apsManager.cgmManager != nil)

            // idea is that we need to avoid retrieving from nightscout
            // while we are at the same time uploading values to nightscout
            // this avoid entries being processed twice

            return Publishers.CombineLatest(
                hasDirectSource ? self.fetchFromCGMManager() : self.nightscoutManager.fetchGlucose(),
                self.fetchGlucoseFromSharedGroup()
            )
        }

    private func subscribe() {
        timer.publisher
            .receive(on: processQueue)
            .flatMap { date -> AnyPublisher<(Date, Date, [BloodGlucose]), Never> in
                debug(.nightscout, "FetchGlucoseManager heartbeat")
                debug(.nightscout, "Start fetching glucose")
                return Publishers.CombineLatest3(
                    Just(date),
                    Just(self.glucoseStorage.syncDate()),
                    self.glucoseCombination
                        .map { [$0, $1].flatMap { $0 } }
                        .eraseToAnyPublisher()
                )
                .eraseToAnyPublisher()
            }

            .sink { date, syncDate, glucose in
                // Because of Spike dosn't respect a date query
                let filteredByDate = glucose.filter { $0.dateString > syncDate }
                let filtered = self.glucoseStorage.filterTooFrequentGlucose(filteredByDate, at: syncDate)
                if !filtered.isEmpty {
                    debug(.nightscout, "New glucose found:: \(String(describing: filtered))")
                    self.glucoseStorage.storeGlucose(filtered)
                    self.apsManager.heartbeat(date: date, force: false)
                }
            }
            .store(in: &lifetime)
        timer.fire()
        timer.resume()
    }

    private func fetchGlucoseFromSharedGroup() -> AnyPublisher<[BloodGlucose], Never> {
        guard let suiteName = Bundle.main.appGroupSuiteName,
              let sharedDefaults = UserDefaults(suiteName: suiteName)
        else {
            return Just([]).eraseToAnyPublisher()
        }

        return Just(fetchLastBGs(60, sharedDefaults)).eraseToAnyPublisher()
    }

    private func fetchLastBGs(_ count: Int, _ sharedDefaults: UserDefaults) -> [BloodGlucose] {
        guard let sharedData = sharedDefaults.data(forKey: "latestReadings") else {
            return []
        }

        let decoded = try? JSONSerialization.jsonObject(with: sharedData, options: [])
        guard let sgvs = decoded as? [AnyObject] else {
            return []
        }

        var results: [BloodGlucose] = []
        for sgv in sgvs.prefix(count) {
            guard
                let glucose = sgv["Value"] as? Int,
                let direction = sgv["direction"] as? String,
                let timestamp = sgv["DT"] as? String,
                let date = parseDate(timestamp)
            else { continue }

            results.append(
                BloodGlucose(
                    _id: UUID().uuidString,
                    sgv: glucose,
                    direction: BloodGlucose.Direction(rawValue: direction),
                    date: Decimal(Int(date.timeIntervalSince1970 * 1000)),
                    dateString: date,
                    filtered: nil,
                    noise: nil,
                    glucose: glucose
                )
            )
        }
        return results
    }

    private func parseDate(_ timestamp: String) -> Date? {
        // timestamp looks like "/Date(1462404576000)/"
        guard let re = try? NSRegularExpression(pattern: "\\((.*)\\)"),
              let match = re.firstMatch(in: timestamp, range: NSMakeRange(0, timestamp.count))
        else {
            return nil
        }

        let matchRange = match.range(at: 1)
        let epoch = Double((timestamp as NSString).substring(with: matchRange))! / 1000
        return Date(timeIntervalSince1970: epoch)
    }
}

public extension Bundle {
    var appGroupSuiteName: String? {
        object(forInfoDictionaryKey: "AppGroupID") as? String
    }
}
