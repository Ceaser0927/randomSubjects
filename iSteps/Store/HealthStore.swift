import Foundation
import HealthKit

class HealthStore {

    var healthStore: HKHealthStore?
    var query: HKStatisticsCollectionQuery?

    init() {
        if HKHealthStore.isHealthDataAvailable() {
            healthStore = HKHealthStore()
        }
    }

    func calculateSteps(completion: @escaping (HKStatisticsCollection?) -> Void) {
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())
        let anchorDate = Date.mondayAt12AM()
        let daily = DateComponents(day: 1)
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: Date(),
            options: .strictStartDate
        )

        query = HKStatisticsCollectionQuery(
            quantityType: stepType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum,
            anchorDate: anchorDate,
            intervalComponents: daily
        )

        query?.initialResultsHandler = { _, statisticsCollection, _ in
            completion(statisticsCollection)
        }

        if let healthStore = healthStore, let query = self.query {
            healthStore.execute(query)
        }
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard let healthStore = self.healthStore else {
            return completion(false)
        }

        var readTypes = Set<HKObjectType>()

        // Activity / Fitness
        addQuantity(.stepCount, to: &readTypes)
        addQuantity(.distanceWalkingRunning, to: &readTypes)
        addQuantity(.flightsClimbed, to: &readTypes)
        addQuantity(.activeEnergyBurned, to: &readTypes)
        addQuantity(.basalEnergyBurned, to: &readTypes)
        addQuantity(.appleExerciseTime, to: &readTypes)
        addQuantity(.appleMoveTime, to: &readTypes)
        addQuantity(.appleStandTime, to: &readTypes)

        // Heart
        addQuantity(.heartRate, to: &readTypes)
        addQuantity(.restingHeartRate, to: &readTypes)
        addQuantity(.walkingHeartRateAverage, to: &readTypes)
        addQuantity(.heartRateVariabilitySDNN, to: &readTypes)

        // Sleep
        addCategory(.sleepAnalysis, to: &readTypes)

        // Respiration / Blood Oxygen
        addQuantity(.respiratoryRate, to: &readTypes)
        addQuantity(.oxygenSaturation, to: &readTypes)

        // Body / Metabolic
        addQuantity(.bodyMass, to: &readTypes)
        addQuantity(.bodyMassIndex, to: &readTypes)
        addQuantity(.bodyFatPercentage, to: &readTypes)
        addQuantity(.vo2Max, to: &readTypes)

        // Workouts
        readTypes.insert(HKObjectType.workoutType())

        // Mindfulness
        addCategory(.mindfulSession, to: &readTypes)

        healthStore.requestAuthorization(toShare: [], read: readTypes) { success, _ in
            completion(success)
        }
    }

    private func addQuantity(_ id: HKQuantityTypeIdentifier, to set: inout Set<HKObjectType>) {
        if let t = HKObjectType.quantityType(forIdentifier: id) {
            set.insert(t)
        }
    }

    private func addCategory(_ id: HKCategoryTypeIdentifier, to set: inout Set<HKObjectType>) {
        if let t = HKObjectType.categoryType(forIdentifier: id) {
            set.insert(t)
        }
    }
}
