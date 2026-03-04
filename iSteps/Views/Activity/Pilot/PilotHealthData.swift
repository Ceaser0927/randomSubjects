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

        let range = dayRange(for: date)
        let predicate = HKQuery.predicateForSamples(withStart: range.start, end: range.end, options: .strictStartDate)

        let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
            if error != nil { return completion(nil) }
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
            for item in s {
                let v = item.value
                let asleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue
                ]
                if asleepValues.contains(v) {
                    totalSeconds += item.endDate.timeIntervalSince(item.startDate)
                }
            }

            let hours = totalSeconds / 3600.0
            completion(hours > 0 ? hours : nil)
        }

        hk.execute(q)
    }
}
