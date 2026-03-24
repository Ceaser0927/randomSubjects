import Foundation
import HealthKit

extension PilotLandingView {

    // MARK: - Health checks

    func requiredReadTypes() -> Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        ]

        if let respiratoryRate = HKObjectType.quantityType(forIdentifier: .respiratoryRate) {
            types.insert(respiratoryRate)
        }

        if let oxygenSaturation = HKObjectType.quantityType(forIdentifier: .oxygenSaturation) {
            types.insert(oxygenSaturation)
        }

        return types
    }

    func refreshAllStatuses() {
        lastSyncEpoch = Date().timeIntervalSince1970

        refreshHealthAuthorizationReliable {
            self.watchLikelyConnected = self.healthAuthorized
            self.refreshTodaySignals()

            self.nextSurveyText = "Not scheduled"
            self.surveyOverdue = false
        }
    }

    func refreshHealthAuthorizationReliable(completion: @escaping () -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            healthAuthorized = false
            completion()
            return
        }

        let types = requiredReadTypes()

        hk.getRequestStatusForAuthorization(toShare: [], read: types) { status, _ in
            DispatchQueue.main.async {
                switch status {
                case .unnecessary:
                    self.verifyReadAccessByQuery(completion: completion)

                case .shouldRequest:
                    self.hk.requestAuthorization(toShare: [], read: types) { _, _ in
                        DispatchQueue.main.async {
                            self.verifyReadAccessByQuery(completion: completion)
                        }
                    }

                @unknown default:
                    self.healthAuthorized = false
                    completion()
                }
            }
        }
    }

    func verifyReadAccessByQuery(completion: @escaping () -> Void) {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            healthAuthorized = false
            completion()
            return
        }

        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -1, to: end)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: nil) { _, _, error in
            DispatchQueue.main.async {
                self.healthAuthorized = (error == nil)
                completion()
            }
        }
        hk.execute(q)
    }

    // MARK: - Pilot UI completeness

    func refreshTodaySignals() {
        todaySignals = .loading

        guard healthAuthorized else {
            todaySignals = .result(.init(
                stepsOK: false,
                sleepOK: false,
                hrvOK: false,
                rhrOK: false,
                energyOK: false,
                heartRateOK: false,
                respiratoryOK: false,
                oxygenOK: false
            ))
            return
        }

        let group = DispatchGroup()

        var stepsOK = false
        var sleepOK = false
        var hrvOK = false
        var rhrOK = false
        var energyOK = false
        var heartRateOK = false
        var respiratoryOK = false
        var oxygenOK = false

        group.enter()
        hasTodayCumulative(.stepCount) { found in
            stepsOK = found
            group.leave()
        }

        group.enter()
        hasAnyCategoryLast24h(.sleepAnalysis) { found in
            sleepOK = found
            group.leave()
        }

        group.enter()
        hasAnyQuantityLast24h(.heartRateVariabilitySDNN) { found in
            hrvOK = found
            group.leave()
        }

        group.enter()
        hasAnyQuantityLast24h(.restingHeartRate) { found in
            rhrOK = found
            group.leave()
        }

        group.enter()
        hasTodayCumulative(.activeEnergyBurned) { found in
            energyOK = found
            group.leave()
        }

        group.enter()
        hasAnyQuantityLast24h(.heartRate) { found in
            heartRateOK = found
            group.leave()
        }

        group.enter()
        hasAnyQuantityLast24h(.respiratoryRate) { found in
            respiratoryOK = found
            group.leave()
        }

        group.enter()
        hasAnyQuantityLast24h(.oxygenSaturation) { found in
            oxygenOK = found
            group.leave()
        }

        group.notify(queue: .main) {
            self.todaySignals = .result(.init(
                stepsOK: stepsOK,
                sleepOK: sleepOK,
                hrvOK: hrvOK,
                rhrOK: rhrOK,
                energyOK: energyOK,
                heartRateOK: heartRateOK,
                respiratoryOK: respiratoryOK,
                oxygenOK: oxygenOK
            ))
        }
    }

    func hasTodayCumulative(_ id: HKQuantityTypeIdentifier, completion: @escaping (Bool) -> Void) {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else {
            completion(false)
            return
        }

        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
            guard let sum = stats?.sumQuantity() else {
                completion(false)
                return
            }

            let value: Double
            switch id {
            case .activeEnergyBurned:
                value = sum.doubleValue(for: .kilocalorie())
            default:
                value = sum.doubleValue(for: .count())
            }

            completion(value > 0)
        }

        hk.execute(query)
    }

    func hasAnyQuantityLast24h(_ id: HKQuantityTypeIdentifier, completion: @escaping (Bool) -> Void) {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else {
            completion(false)
            return
        }

        let end = Date()
        let start = Calendar.current.date(byAdding: .hour, value: -24, to: end)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, error in
            if error != nil {
                completion(false)
                return
            }
            completion(!(samples ?? []).isEmpty)
        }
        hk.execute(q)
    }

    func hasAnyCategoryLast24h(_ id: HKCategoryTypeIdentifier, completion: @escaping (Bool) -> Void) {
        guard let type = HKCategoryType.categoryType(forIdentifier: id) else {
            completion(false)
            return
        }

        let end = Date()
        let start = Calendar.current.date(byAdding: .hour, value: -24, to: end)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, error in
            if error != nil {
                completion(false)
                return
            }
            completion(!(samples ?? []).isEmpty)
        }
        hk.execute(q)
    }

    // MARK: - Date helpers

    private func dayRange(for date: Date) -> (start: Date, end: Date) {
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return (start, end)
    }

    private func localDateId(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.calendar = Calendar.current
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone.current
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }

    // MARK: - Numeric queries (by day)

    func fetchCumulativeNumber(for date: Date, _ id: HKQuantityTypeIdentifier, completion: @escaping (Double?) -> Void) {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else {
            completion(nil)
            return
        }

        let range = dayRange(for: date)
        let predicate = HKQuery.predicateForSamples(withStart: range.start, end: range.end, options: .strictStartDate)

        let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, error in
            if error != nil {
                completion(nil)
                return
            }
            guard let sum = stats?.sumQuantity() else {
                completion(nil)
                return
            }

            switch id {
            case .activeEnergyBurned:
                completion(sum.doubleValue(for: .kilocalorie()))
            default:
                completion(sum.doubleValue(for: .count()))
            }
        }

        hk.execute(query)
    }

    func fetchDailyAverage(for date: Date, _ id: HKQuantityTypeIdentifier, completion: @escaping (Double?) -> Void) {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else {
            completion(nil)
            return
        }

        let range = dayRange(for: date)
        let predicate = HKQuery.predicateForSamples(withStart: range.start, end: range.end, options: .strictStartDate)

        let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage) { _, stats, error in
            if error != nil {
                completion(nil)
                return
            }
            guard let avg = stats?.averageQuantity() else {
                completion(nil)
                return
            }

            switch id {
            case .restingHeartRate, .heartRate, .respiratoryRate:
                completion(avg.doubleValue(for: HKUnit.count().unitDivided(by: .minute())))
            case .heartRateVariabilitySDNN:
                completion(avg.doubleValue(for: .secondUnit(with: .milli)))
            case .oxygenSaturation:
                completion(avg.doubleValue(for: .percent()) * 100.0)
            default:
                completion(nil)
            }
        }

        hk.execute(query)
    }

    func fetchHeartRateSummary(for date: Date, completion: @escaping (Double?, Double?, Double?) -> Void) {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            completion(nil, nil, nil)
            return
        }

        let range = dayRange(for: date)
        let predicate = HKQuery.predicateForSamples(withStart: range.start, end: range.end, options: .strictStartDate)
        let options: HKStatisticsOptions = [.discreteAverage, .discreteMin, .discreteMax]

        let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: options) { _, stats, error in
            if error != nil {
                completion(nil, nil, nil)
                return
            }

            let unit = HKUnit.count().unitDivided(by: .minute())
            let avg = stats?.averageQuantity()?.doubleValue(for: unit)
            let min = stats?.minimumQuantity()?.doubleValue(for: unit)
            let max = stats?.maximumQuantity()?.doubleValue(for: unit)

            completion(avg, min, max)
        }

        hk.execute(query)
    }

    func fetchSleepHours(for date: Date, completion: @escaping (Double?) -> Void) {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            completion(nil)
            return
        }

        let cal = Calendar.current
        let anchorStart = cal.startOfDay(for: date)

        let windowStart = cal.date(byAdding: .hour, value: -6, to: anchorStart)!
        let windowEnd = cal.date(byAdding: .hour, value: 12, to: anchorStart)!

        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd, options: [])
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]

        let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: sort) { _, samples, error in
            if error != nil {
                completion(nil)
                return
            }

            let s = (samples as? [HKCategorySample]) ?? []
            if s.isEmpty {
                completion(nil)
                return
            }

            let asleepValues: Set<Int> = [
                HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                HKCategoryValueSleepAnalysis.asleepREM.rawValue
            ]

            func overlapSeconds(_ aStart: Date, _ aEnd: Date) -> TimeInterval {
                let start = max(aStart, windowStart)
                let end = min(aEnd, windowEnd)
                return max(0, end.timeIntervalSince(start))
            }

            var totalSeconds: TimeInterval = 0
            for item in s where asleepValues.contains(item.value) {
                totalSeconds += overlapSeconds(item.startDate, item.endDate)
            }

            let hours = totalSeconds / 3600.0
            completion(hours > 0 ? hours : nil)
        }

        hk.execute(q)
    }

    // MARK: - Last 24h helpers

    func fetchTodayCumulativeNumber(_ id: HKQuantityTypeIdentifier, completion: @escaping (Double?) -> Void) {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else {
            completion(nil)
            return
        }

        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, error in
            if error != nil {
                completion(nil)
                return
            }
            guard let sum = stats?.sumQuantity() else {
                completion(nil)
                return
            }

            switch id {
            case .activeEnergyBurned:
                completion(sum.doubleValue(for: .kilocalorie()))
            default:
                completion(sum.doubleValue(for: .count()))
            }
        }

        hk.execute(query)
    }

    func fetchLast24hAverage(_ id: HKQuantityTypeIdentifier, completion: @escaping (Double?) -> Void) {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else {
            completion(nil)
            return
        }

        let end = Date()
        let start = Calendar.current.date(byAdding: .hour, value: -24, to: end)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage) { _, stats, error in
            if error != nil {
                completion(nil)
                return
            }
            guard let avg = stats?.averageQuantity() else {
                completion(nil)
                return
            }

            switch id {
            case .restingHeartRate, .heartRate, .respiratoryRate:
                completion(avg.doubleValue(for: HKUnit.count().unitDivided(by: .minute())))
            case .heartRateVariabilitySDNN:
                completion(avg.doubleValue(for: .secondUnit(with: .milli)))
            case .oxygenSaturation:
                completion(avg.doubleValue(for: .percent()) * 100.0)
            default:
                completion(nil)
            }
        }

        hk.execute(query)
    }

    func fetchSleepHoursLast24h(completion: @escaping (Double?) -> Void) {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            completion(nil)
            return
        }

        let end = Date()
        let start = Calendar.current.date(byAdding: .hour, value: -24, to: end)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
            if error != nil {
                completion(nil)
                return
            }

            let s = (samples as? [HKCategorySample]) ?? []

            var totalSeconds: TimeInterval = 0
            let asleepValues: Set<Int> = [
                HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                HKCategoryValueSleepAnalysis.asleepREM.rawValue
            ]

            for item in s where asleepValues.contains(item.value) {
                totalSeconds += item.endDate.timeIntervalSince(item.startDate)
            }

            let hours = totalSeconds / 3600.0
            completion(hours > 0 ? hours : nil)
        }

        hk.execute(q)
    }

    // MARK: - Nightly sleep payload

    struct SleepNightlyPayload {
        let sleepKey: String
        let anchorDateLocal: String
        let anchorRule: String
        let startTimeUTC: Double
        let endTimeUTC: Double
        let timezone: String
        let deepMin: Int
        let coreMin: Int
        let remMin: Int
        let awakeMin: Int
        let asleepMin: Int
        let hasStages: Bool
        let respiratoryRateAvg: Double?
    }

    func fetchNightlySleepStages(anchorDate: Date, completion: @escaping (SleepNightlyPayload?) -> Void) {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            completion(nil)
            return
        }

        let cal = Calendar.current
        let anchorStart = cal.startOfDay(for: anchorDate)

        let windowStart = cal.date(byAdding: .hour, value: -6, to: anchorStart)!
        let windowEnd = cal.date(byAdding: .hour, value: 12, to: anchorStart)!

        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd, options: .strictStartDate)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]

        let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: sort) { _, samples, error in
            if error != nil {
                completion(nil)
                return
            }

            let s = (samples as? [HKCategorySample]) ?? []
            if s.isEmpty {
                completion(nil)
                return
            }

            let asleepValues: Set<Int> = [
                HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                HKCategoryValueSleepAnalysis.asleepREM.rawValue
            ]

            let asleepSamples = s.filter { asleepValues.contains($0.value) }
            guard let mainStart = asleepSamples.map(\.startDate).min(),
                  let mainEnd = asleepSamples.map(\.endDate).max(),
                  mainEnd > mainStart else {
                completion(nil)
                return
            }

            func overlapSeconds(_ aStart: Date, _ aEnd: Date) -> TimeInterval {
                let start = max(aStart, mainStart)
                let end = min(aEnd, mainEnd)
                return max(0, end.timeIntervalSince(start))
            }

            var deepSec: TimeInterval = 0
            var coreSec: TimeInterval = 0
            var remSec: TimeInterval = 0
            var awakeSec: TimeInterval = 0
            var asleepSec: TimeInterval = 0

            var sawDeep = false
            var sawCore = false
            var sawREM = false

            for item in s {
                let sec = overlapSeconds(item.startDate, item.endDate)
                if sec <= 0 { continue }

                switch item.value {
                case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                    deepSec += sec
                    asleepSec += sec
                    sawDeep = true

                case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                    coreSec += sec
                    asleepSec += sec
                    sawCore = true

                case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                    remSec += sec
                    asleepSec += sec
                    sawREM = true

                case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                    asleepSec += sec

                case HKCategoryValueSleepAnalysis.awake.rawValue:
                    awakeSec += sec

                default:
                    break
                }
            }

            let deepMin = Int((deepSec / 60.0).rounded())
            let coreMin = Int((coreSec / 60.0).rounded())
            let remMin = Int((remSec / 60.0).rounded())
            let awakeMin = Int((awakeSec / 60.0).rounded())
            let asleepMin = Int((asleepSec / 60.0).rounded())

            let anchorDateLocal = self.localDateId(anchorDate)
            let timezone = TimeZone.current.identifier
            let startEpoch = mainStart.timeIntervalSince1970
            let endEpoch = mainEnd.timeIntervalSince1970
            let sleepKey = "\(Int(startEpoch))_\(Int(endEpoch))"

            self.fetchAverageRespiratoryRate(from: mainStart, to: mainEnd) { respiratoryRateAvg in
                let payload = SleepNightlyPayload(
                    sleepKey: sleepKey,
                    anchorDateLocal: anchorDateLocal,
                    anchorRule: "wakeDateLocal",
                    startTimeUTC: startEpoch,
                    endTimeUTC: endEpoch,
                    timezone: timezone,
                    deepMin: deepMin,
                    coreMin: coreMin,
                    remMin: remMin,
                    awakeMin: awakeMin,
                    asleepMin: asleepMin,
                    hasStages: (sawDeep || sawCore || sawREM),
                    respiratoryRateAvg: respiratoryRateAvg
                )

                completion(payload)
            }
        }

        hk.execute(q)
    }

    func fetchAverageRespiratoryRate(from start: Date, to end: Date, completion: @escaping (Double?) -> Void) {
        guard let type = HKQuantityType.quantityType(forIdentifier: .respiratoryRate) else {
            completion(nil)
            return
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage) { _, stats, error in
            if error != nil {
                completion(nil)
                return
            }

            guard let avg = stats?.averageQuantity() else {
                completion(nil)
                return
            }

            let value = avg.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            completion(value)
        }

        hk.execute(query)
    }
}
