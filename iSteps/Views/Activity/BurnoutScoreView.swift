import SwiftUI
import GaugeKit
import SafariServices

struct BurnoutScoreView: View {

    var steps: [Step]

    // ✅ Survey moved to Home (top-right doc button)
    @State private var isSurveyPresented = false

    // MARK: - Simple rule algorithm (replace later with ML model)
    // When no data, return nil (so UI can show No Data state)
    private func calculateBurnoutRisk() -> (score: Int, label: String, confidence: Int, totalSteps: Int)? {
        let totalSteps = steps.map { $0.count }.reduce(0, +)

        // 关键：没有任何有效步数，就认为没数据
        guard totalSteps > 0 else { return nil }

        // Simple logic: fewer steps -> higher risk
        let maxSteps = 14000
        let minSteps = 2000

        let clamped = max(minSteps, min(maxSteps, totalSteps))
        let ratio = Double(maxSteps - clamped) / Double(maxSteps - minSteps)
        let score = Int((ratio * 100).rounded())

        let label: String
        switch score {
        case 0..<35: label = "Low"
        case 35..<70: label = "Moderate"
        default: label = "High"
        }

        // AI-ish confidence: more days -> higher confidence (placeholder)
        let days = steps.count
        let confidence = min(95, max(55, 55 + (days * 6)))

        return (score, label, confidence, totalSteps)
    }

    // Left green -> right red
    private let gaugeColors: [Color] = [.green, .yellow, .orange, .red]

    var body: some View {
        let result = calculateBurnoutRisk()
        let gaugeValue = result?.score ?? 0

        NavigationView {
            ZStack {
                LinearGradient(
                    colors: [
                        Color.black,
                        Color(red: 0.07, green: 0.08, blue: 0.12),
                        Color(red: 0.10, green: 0.07, blue: 0.16)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {

                        aiHeaderCard(result: result)

                        // Gauge card
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Risk Score")
                                    .font(.system(.headline, design: .rounded).weight(.semibold))
                                    .foregroundColor(.white)
                                Spacer()
                                Text("0—100")
                                    .font(.system(.caption, design: .rounded).weight(.semibold))
                                    .foregroundColor(.white.opacity(0.6))
                            }

                            Divider().overlay(.white.opacity(0.12))

                            HStack(alignment: .center, spacing: 16) {

                                // ✅ GaugeKit
                                GaugeView(
                                    title: "Burnout Risk",
                                    value: gaugeValue,
                                    maxValue: 100,
                                    colors: gaugeColors
                                )
                                .gaugeMeterThickness(22)
                                .gaugeMeterShadow(color: .black.opacity(0.25), radius: 6)
                                .frame(width: 190, height: 190)
                                .overlay(
                                    Group {
                                        if result == nil {
                                            VStack(spacing: 6) {
                                                Text("NO DATA")
                                                    .font(.system(.caption, design: .rounded).weight(.bold))
                                                    .foregroundColor(.white.opacity(0.9))
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 6)
                                                    .background(.black.opacity(0.35))
                                                    .clipShape(Capsule())

                                                Text("Sync required")
                                                    .font(.system(.caption2, design: .rounded))
                                                    .foregroundColor(.white.opacity(0.7))
                                            }
                                        }
                                    }
                                )

                                VStack(alignment: .leading, spacing: 10) {

                                    if let result = result {
                                        Text("\(result.score)/100")
                                            .font(.system(.title2, design: .rounded).weight(.bold))
                                            .foregroundColor(.white)

                                        Text(result.label.uppercased())
                                            .font(.system(.caption, design: .rounded).weight(.bold))
                                            .foregroundColor(.white.opacity(0.85))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(.white.opacity(0.08))
                                            .clipShape(Capsule())

                                        Text("Confidence: \(result.confidence)%")
                                            .font(.system(.footnote, design: .rounded))
                                            .foregroundColor(.white.opacity(0.7))

                                        Text("Explanation: lower weekly steps → higher risk.")
                                            .font(.system(.footnote, design: .rounded))
                                            .foregroundColor(.white.opacity(0.6))
                                    } else {
                                        Text("—/100")
                                            .font(.system(.title2, design: .rounded).weight(.bold))
                                            .foregroundColor(.white)

                                        Text("AWAITING SYNC")
                                            .font(.system(.caption, design: .rounded).weight(.bold))
                                            .foregroundColor(.white.opacity(0.85))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(.white.opacity(0.08))
                                            .clipShape(Capsule())

                                        Text("Connect Apple Watch data to generate a score.")
                                            .font(.system(.footnote, design: .rounded))
                                            .foregroundColor(.white.opacity(0.6))

                                        HStack(spacing: 10) {
                                            pill("HealthKit", icon: "heart.fill")
                                            pill("Watch", icon: "applewatch")
                                        }
                                    }

                                    Spacer(minLength: 0)
                                }

                                Spacer(minLength: 0)
                            }
                        }
                        .padding(16)
                        .background(.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(.white.opacity(0.10), lineWidth: 1)
                        )

                        // ✅ Weekly Summary card (product card under Home)
                        weeklySummaryCard()

                        // Insights card
                        insightsCard(result: result)

                        Spacer(minLength: 18)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 90) // avoid tab bar overlap
                }
            }
            .navigationTitle("Score")
            .navigationBarTitleDisplayMode(.inline)
            // ✅ Survey button (moved here)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isSurveyPresented = true
                    } label: {
                        Image(systemName: "doc.text")
                    }
                    .sheet(isPresented: $isSurveyPresented) {
                        SafariView(url: URL(string: "https://form.typeform.com/to/STFEkNs0")!)
                    }
                }
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func aiHeaderCard(result: (score: Int, label: String, confidence: Int, totalSteps: Int)?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(10)
                    .background(.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Burnout Monitor")
                        .font(.system(.headline, design: .rounded).weight(.semibold))
                        .foregroundColor(.white)
                    Text("Activity-driven risk estimate (prototype)")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(.white.opacity(0.65))
                }

                Spacer()

                Text(result == nil ? "NO DATA" : "READY")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundColor(result == nil ? .white.opacity(0.8) : .green.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.08))
                    .clipShape(Capsule())
            }

            Divider().overlay(.white.opacity(0.12))

            if let result = result {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Model Output")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundColor(.white.opacity(0.6))
                        Text("\(result.label) risk predicted")
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Confidence")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundColor(.white.opacity(0.6))
                        Text("\(result.confidence)%")
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .foregroundColor(.white)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Awaiting signal")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundColor(.white)
                    Text("Sync Apple Watch activity data to generate an AI estimate.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(.white.opacity(0.65))
                }
            }
        }
        .padding(16)
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
    }

    // MARK: - Weekly Summary (product card)

    @ViewBuilder
    private func weeklySummaryCard() -> some View {
        let s = weeklySummary()

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("This Week Summary")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: "calendar")
                    .foregroundColor(.white.opacity(0.7))
            }

            Divider().overlay(.white.opacity(0.12))

            if s.scoredDays < 3 {
                Text("Not enough data yet.")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundColor(.white)

                Text("We’ll generate a weekly summary once we have at least 3 days of activity data.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))
            } else {
                HStack(spacing: 12) {
                    miniStat(title: "Avg risk", value: "\(s.avgScore)")
                    miniStat(title: "Trend", value: s.deltaText)
                    miniStat(title: "Data", value: "\(s.scoredDays)/7")
                }

                Text(s.oneLine)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func miniStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundColor(.white.opacity(0.6))
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundColor(.white)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func weeklySummary() -> (avgScore: Int, deltaText: String, scoredDays: Int, oneLine: String) {
        // Use up to last 7 records; if you store per-day steps this is perfect.
        let recent = Array(steps.suffix(7))
        let valid = recent.filter { $0.count > 0 }
        let scoredDays = valid.count

        guard scoredDays > 0 else {
            return (0, "—", 0, "No data available.")
        }

        // Day-level score from steps (same heuristic)
        func dayScore(_ s: Int) -> Int {
            let maxSteps = 14000
            let minSteps = 2000
            let clamped = max(minSteps, min(maxSteps, s))
            let ratio = Double(maxSteps - clamped) / Double(maxSteps - minSteps)
            return Int((ratio * 100).rounded())
        }

        let scores = valid.map { dayScore($0.count) }
        let avg = Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())

        // Delta: last valid - first valid
        let delta = (scores.last ?? avg) - (scores.first ?? avg)
        let deltaText: String = delta > 0 ? "+\(delta)" : "\(delta)"

        // One-line summary (pilot-friendly wording)
        let line: String
        if delta >= 12 {
            line = "Strain appears to be increasing this week. Consider prioritizing recovery and sleep."
        } else if delta <= -12 {
            line = "Strain is trending down this week. Nice—keep your recovery habits consistent."
        } else {
            line = "Strain is relatively stable this week. Keep an eye on rest and workload balance."
        }

        return (avg, deltaText, scoredDays, line)
    }

    // MARK: - Insights

    @ViewBuilder
    private func insightsCard(result: (score: Int, label: String, confidence: Int, totalSteps: Int)?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Signals & Insights")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.white.opacity(0.7))
            }

            Divider().overlay(.white.opacity(0.12))

            if let result = result {
                insightRow(
                    title: "Weekly steps",
                    value: "\(result.totalSteps)",
                    subtitle: "Sum of available days",
                    icon: "figure.walk"
                )

                insightRow(
                    title: "Decision rule",
                    value: "Steps → Risk",
                    subtitle: "Prototype heuristic (replace with ML)",
                    icon: "function"
                )

                insightRow(
                    title: "Next features",
                    value: "HRV • Sleep • RHR",
                    subtitle: "Add signals to improve accuracy",
                    icon: "plus.circle"
                )

                Text("Tip: show “model-ready” once HealthKit returns 5–7 days.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.top, 4)
            } else {
                Text("No signals detected yet.")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundColor(.white)

                Text("Once we have activity data, we’ll generate a score and provide feature attribution here.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))
            }
        }
        .padding(16)
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
    }

    // MARK: - Small UI helpers

    private func pill(_ text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.system(.caption, design: .rounded).weight(.semibold))
        .foregroundColor(.white.opacity(0.85))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white.opacity(0.08))
        .clipShape(Capsule())
    }

    private func insightRow(title: String, value: String, subtitle: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 28, height: 28)
                .background(.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Text(value)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundColor(.white.opacity(0.9))
                }
                Text(subtitle)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(12)
        .background(.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }
}



struct BurnoutScoreView_Previews: PreviewProvider {
    static var previews: some View {
        BurnoutScoreView(steps: [])
            .preferredColorScheme(.dark)
    }
}
