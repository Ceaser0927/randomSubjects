import Foundation
import HealthKit

extension PilotLandingView {

    // MARK: - Health checks (best-effort)

    func requiredReadTypes() -> Set<HKObjectType> {
        return [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        ]
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

    // MARK: - Existing signal completeness UI (Bool-based)

    func refreshTodaySignals() {
        todaySignals = .loading

        guard healthAuthorized else {
            todaySignals = .result(.init(stepsOK: false, sleepOK: false, hrvOK: false, rhrOK: false, energyOK: false))
            return
        }

        let group = DispatchGroup()
        var stepsOK = false
        var sleepOK = false
        var hrvOK = false
        var rhrOK = false
        var energyOK = false

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

        group.notify(queue: .main) {
            self.todaySignals = .result(.init(
                stepsOK: stepsOK,
                sleepOK: sleepOK,
                hrvOK: hrvOK,
                rhrOK: rhrOK,
                energyOK: energyOK
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
            if error != nil { return completion(false) }
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
            if error != nil { return completion(false) }
            completion(!(samples ?? []).isEmpty)
        }
        hk.execute(q)
    }

    // MARK: - Date-range helpers

    private func dayRange(for date: Date) -> (start: Date, end: Date) {
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return (start, end)
    }

    /// Formats a date into "yyyy-MM-dd" using the user's current locale/timezone.
    private func localDateId(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.calendar = Calendar.current
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone.current
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }

    // MARK: - Numeric queries (by day) for backfill uploads

    func fetchCumulativeNumber(for date: Date, _ id: HKQuantityTypeIdentifier, completion: @escaping (Double?) -> Void) {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else {
            completion(nil)
            return
        }

        let range = dayRange(for: date)
        let predicate = HKQuery.predicateForSamples(withStart: range.start, end: range.end, options: .strictStartDate)

        let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, error in
            if error != nil { return completion(nil) }
            guard let sum = stats?.sumQuantity() else { return completion(nil) }

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
            if error != nil { return completion(nil) }
            guard let avg = stats?.averageQuantity() else { return completion(nil) }

            switch id {
            case .restingHeartRate:
                completion(avg.doubleValue(for: HKUnit.count().unitDivided(by: .minute())))
            case .heartRateVariabilitySDNN:
                completion(avg.doubleValue(for: .secondUnit(with: .milli)))
            default:
                completion(nil)
            }
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

        // Wake-up day window: previous day 18:00 -> anchor day 12:00
        let windowStart = cal.date(byAdding: .hour, value: -6, to: anchorStart)!
        let windowEnd = cal.date(byAdding: .hour, value: 12, to: anchorStart)!

        // IMPORTANT: Do not use strictStartDate; we want overlap across midnight.
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd, options: [])

        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: sort) { _, samples, error in
            if error != nil { return completion(nil) }
            let s = (samples as? [HKCategorySample]) ?? []
            print("🟦 fetchSleepHours raw sample count = \(s.count)")
            if s.isEmpty { return completion(nil) }

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

    // MARK: - Numeric queries for Upload Now

    func fetchTodayCumulativeNumber(_ id: HKQuantityTypeIdentifier, completion: @escaping (Double?) -> Void) {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else {
            completion(nil)
            return
        }

        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, error in
            if error != nil { return completion(nil) }
            guard let sum = stats?.sumQuantity() else { return completion(nil) }

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
            if error != nil { return completion(nil) }
            guard let avg = stats?.averageQuantity() else { return completion(nil) }

            switch id {
            case .restingHeartRate:
                completion(avg.doubleValue(for: HKUnit.count().unitDivided(by: .minute())))
            case .heartRateVariabilitySDNN:
                completion(avg.doubleValue(for: .secondUnit(with: .milli)))
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
            if error != nil { return completion(nil) }
            let s = (samples as? [HKCategorySample]) ?? []

            // Sum only "asleep" categories.
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

    // MARK: - Nightly sleep (research-grade) for sleep_nightly

    /// A minimal, research-grade nightly sleep payload that supports:
    /// - Unique sleepKey (to avoid overwriting when multiple sleeps exist on the same day)
    /// - Anchor date (the "wake-up day" local date used for grouping/joining to daily/{yyyy-MM-dd})
    /// - Start/end timestamps in UTC epoch seconds for reproducibility
    /// - Sleep stages in minutes (Deep/Core/REM/Awake + total asleep)
    struct SleepNightlyPayload {
        let sleepKey: String

        /// Local date used to attach this sleep to daily/{yyyy-MM-dd}.
        /// Example: if you use "wake-up day", then this equals endDateLocal's yyyy-MM-dd.
        let anchorDateLocal: String

        /// A human-readable tag describing the anchoring rule.
        /// Example: "wakeDateLocal"
        let anchorRule: String

        /// UTC epoch seconds (Double) for reproducibility.
        let startTimeUTC: Double
        let endTimeUTC: Double

        /// Timezone identifier at collection time (useful for later audits).
        let timezone: String

        /// Sleep stage minutes (integers).
        let deepMin: Int
        let coreMin: Int
        let remMin: Int
        let awakeMin: Int
        let asleepMin: Int

        /// True if stage-level categories exist (Deep/Core/REM present).
        let hasStages: Bool
    }

    /// Fetches a nightly sleep structure for an anchor date (typically "wake-up day").
    ///
    /// Design notes:
    /// - We DO NOT use anchorDate as docId. Instead, we generate a unique sleepKey derived from start/end epochs.
    /// - We query a wide window that should cover the main night sleep:
    ///   previous day 18:00 -> anchor day 12:00 (local time).
    /// - We select a "main sleep interval" using the earliest asleep start and latest asleep end within the window.
    ///   This is intentionally simple for Pilot. You can refine later (e.g., detect naps vs main sleep).
    func fetchNightlySleepStages(anchorDate: Date, completion: @escaping (SleepNightlyPayload?) -> Void) {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            completion(nil)
            return
        }

        let cal = Calendar.current
        let anchorStart = cal.startOfDay(for: anchorDate)

        // A wide window to capture overnight sleep anchored to the "wake-up day".
        // Example: for 2026-03-08 (local), window is 2026-03-07 18:00 -> 2026-03-08 12:00.
        let windowStart = cal.date(byAdding: .hour, value: -6, to: anchorStart)!  // previous day 18:00
        let windowEnd = cal.date(byAdding: .hour, value: 12, to: anchorStart)!    // anchor day 12:00

        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd, options: .strictStartDate)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]

        let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: sort) { _, samples, error in
            if error != nil {
                return completion(nil)
            }

            let s = (samples as? [HKCategorySample]) ?? []
            if s.isEmpty {
                return completion(nil)
            }

            // Categories considered "asleep".
            let asleepValues: Set<Int> = [
                HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                HKCategoryValueSleepAnalysis.asleepREM.rawValue
            ]

            // Identify the main sleep interval in this window.
            let asleepSamples = s.filter { asleepValues.contains($0.value) }
            guard let mainStart = asleepSamples.map(\.startDate).min(),
                  let mainEnd = asleepSamples.map(\.endDate).max(),
                  mainEnd > mainStart
            else {
                return completion(nil)
            }

            // Helper to accumulate overlap seconds with [mainStart, mainEnd].
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
                    // Unspecified asleep contributes to total asleep, but not to stage buckets.
                    asleepSec += sec

                case HKCategoryValueSleepAnalysis.awake.rawValue:
                    // Awake during a sleep interval.
                    awakeSec += sec

                default:
                    // Ignore other categories (e.g., inBed) for now to keep semantics clean.
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

            // Unique sleep key to avoid overwriting (supports multiple sleeps per day).
            let startEpoch = mainStart.timeIntervalSince1970
            let endEpoch = mainEnd.timeIntervalSince1970
            let sleepKey = "\(Int(startEpoch))_\(Int(endEpoch))"

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
                hasStages: (sawDeep || sawCore || sawREM)
            )

            completion(payload)
        }

        hk.execute(q)
    }
}
