//
//  ContentView.swift
//  iSteps
//


import SwiftUI
import HealthKit

struct ContentView: View {

    private var healthStore: HealthStore?
    @State private var steps: [Step] = []

    init() {
        healthStore = HealthStore()
    }

//    private func updateUIFromStatistics(_ statisticsCollection: HKStatisticsCollection) {
//
//        let today = Date()
//        let calendar = Calendar.current
//        let week = calendar.dateInterval(of: .weekOfMonth, for: today)
//
//        guard let firstWeekDay = week?.start else { return }
//        guard let lastWeekDay = week?.end else { return }
//
//        // Reset to avoid duplicate accumulation on repeated loads.
//        var newSteps: [Step] = []
//
//        statisticsCollection.enumerateStatistics(from: firstWeekDay, to: lastWeekDay - 1) { (statistics, _) in
//            let count = statistics.sumQuantity()?.doubleValue(for: .count())
//            let step = Step(count: Int(count ?? 0), date: statistics.startDate)
//            newSteps.append(step)
//        }
//
//        // Update UI on main thread.
//        DispatchQueue.main.async {
//            self.steps = newSteps
//        }
//    }
    private func updateUIFromStatistics(_ statisticsCollection: HKStatisticsCollection) {
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -7, to: endDate)!

        var newSteps: [Step] = []
        statisticsCollection.enumerateStatistics(from: startDate, to: endDate) { statistics, _ in
            let count = statistics.sumQuantity()?.doubleValue(for: .count()) ?? 0
            newSteps.append(Step(count: Int(count), date: statistics.startDate))
        }

        DispatchQueue.main.async { self.steps = newSteps }
    }
    var body: some View {
        // IMPORTANT:
        // Do NOT wrap TabView inside NavigationStack here,
        // because each child page already owns its own NavigationView.
        // Nested navigation containers often cause missing titles.
        TabView {
            BurnoutScoreView(steps: steps)
                .tabItem {
                    Image(systemName: "gauge.high")
                    Text("Home")
                }

            ActivityView(steps: steps)
                .tabItem {
                    Image(systemName: "target")
                    Text("Activity")
                }

            TrendsView(steps: steps)
                .tabItem {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                    Text("Trends")
                }

            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape")
                    Text("Settings")
                }
        }
        .onAppear {
            guard let healthStore = healthStore else { return }

            healthStore.requestAuthorization { success in
                guard success else { return }

                healthStore.calculateSteps { statisticsCollection in
                    guard let statisticsCollection = statisticsCollection else { return }
                    updateUIFromStatistics(statisticsCollection)
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
