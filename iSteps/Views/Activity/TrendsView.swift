//
//  TrendsView.swift
//  iSteps
//
//  Generated patch - adapted to avoid redeclarations
//

import SwiftUI
#if canImport(Charts)
import Charts
#endif

// NOTE:
// This file intentionally DOES NOT declare `struct Step` or the Date extension
// to avoid duplicate-declaration errors if those exist elsewhere in your project.
// If you want the preview to show mock data, paste your project's Step struct here
// or send me its exact fields and I will provide a preview that matches.

// ---------------------------
// TrendsView
// ---------------------------
struct TrendsView: View {

    // Use your app's Step model here
    var steps: [Step]

    // Risk point (score optional => nil means missing/no-data)
    struct RiskPoint: Identifiable {
        let id = UUID()
        let date: Date
        let steps: Int
        let score: Int?    // nil == no data for that day
        let label: String?
    }

    // Config (same heuristic as Score)
    private let maxSteps = 14_000
    private let minSteps = 2_000
    private let calendar = Calendar.current

    // Build daily series (group by day)
    private var dailySeries: [RiskPoint] {
        // group steps by start of day
        let grouped = Dictionary(grouping: steps) { s in
            // adapt this if your Step uses another property for date (e.g. startDate)
            calendar.startOfDay(for: s.date)
        }

        let pairs = grouped.map { (day, items) -> (Date, Int) in
            (day, items.map { $0.count }.reduce(0, +))
        }
        .sorted { $0.0 < $1.0 }

        return pairs.map { (day, totalSteps) in
            if totalSteps <= 0 {
                return RiskPoint(date: day, steps: totalSteps, score: nil, label: nil)
            } else {
                let (score, label) = burnoutScoreFromSteps(totalSteps)
                return RiskPoint(date: day, steps: totalSteps, score: score, label: label)
            }
        }
    }

    // helper: last N days from the series
    private func lastDays(_ n: Int) -> [RiskPoint] {
        Array(dailySeries.suffix(n))
    }

    // Derived
    private var hasAnyData: Bool { dailySeries.contains { $0.score != nil } }
    private var last7: [RiskPoint] { lastDays(7) }
    private var pointsForChart: [RiskPoint] { last7.filter { $0.score != nil } }

    private var latest: RiskPoint? {
        dailySeries.reversed().first(where: { $0.score != nil })
    }

    private var avg7: Int {
        let vals = last7.compactMap { $0.score }
        guard !vals.isEmpty else { return 0 }
        let v = Double(vals.reduce(0, +)) / Double(vals.count)
        return Int(v.rounded())
    }

    private var delta7: Int {
        let vals = last7.compactMap { $0.score }
        guard vals.count >= 2 else { return 0 }
        return vals.last! - vals.first!
    }

    // Heuristic scoring (same as Score)
    private func burnoutScoreFromSteps(_ totalSteps: Int) -> (Int, String) {
        let clamped = max(minSteps, min(maxSteps, totalSteps))
        let ratio = Double(maxSteps - clamped) / Double(maxSteps - minSteps)
        let score = Int((ratio * 100).rounded())
        let label: String
        switch score {
        case 0..<35: label = "Low"
        case 35..<70: label = "Moderate"
        default: label = "High"
        }
        return (score, label)
    }

    // Body
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(colors: [
                    Color.black,
                    Color(red: 0.07, green: 0.08, blue: 0.12),
                    Color(red: 0.10, green: 0.07, blue: 0.16)
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        headerCard

                        if hasAnyData {
                            HStack(spacing: 12) {
                                smallStatCard(title: "Latest", value: latest?.score.map { "\($0)" } ?? "—", subtitle: latest?.label ?? "No data", icon: "bolt.heart")
                                smallStatCard(title: "Avg (7d)", value: "\(avg7)", subtitle: "7-day mean", icon: "sum")
                                smallStatCard(title: "Δ (7d)", value: deltaText(delta7), subtitle: "trend", icon: "arrow.up.right")
                            }

                            glassCard(title: "Risk Trend", trailingIcon: "chart.xyaxis.line") {
                                riskChart(points: pointsForChart)
                                    .frame(height: 200)
                                    .padding(.top, 6)

                                Text("Heuristic estimate. Replace with ML model output later.")
                                    .font(.system(.footnote, design: .rounded))
                                    .foregroundColor(.white.opacity(0.55))
                                    .padding(.top, 8)
                            }
                        } else {
                            glassCard(title: "Risk Trend", trailingIcon: "chart.xyaxis.line") {
                                VStack {
                                    Text("No scored days yet.")
                                        .font(.system(.headline, design: .rounded).weight(.semibold))
                                        .foregroundColor(.white)
                                    Text("Days with zero steps are treated as missing. Sync your Apple Watch / HealthKit to populate daily steps.")
                                        .font(.system(.subheadline, design: .rounded))
                                        .foregroundColor(.white.opacity(0.65))
                                        .multilineTextAlignment(.center)
                                }
                                .padding(.vertical, 12)
                            }
                        }

                        glassCard(title: "Recent Days", trailingIcon: "calendar") {
                            VStack(spacing: 10) {
                                ForEach(last7.reversed()) { p in
                                    recentRow(p)
                                }
                            }
                        }

                        Spacer(minLength: 18)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 90)
                }
            }
            .navigationTitle("Trends")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // Components
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(10)
                    .background(.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Risk Trends")
                        .font(.system(.headline, design: .rounded).weight(.semibold))
                        .foregroundColor(.white)
                    Text("Time-series of burnout risk estimates")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(.white.opacity(0.65))
                }

                Spacer()

                Text(hasAnyData ? "READY" : "NO DATA")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundColor(hasAnyData ? .green.opacity(0.9) : .white.opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.08))
                    .clipShape(Capsule())
            }

            Divider().overlay(.white.opacity(0.12))

            if let latest = latest, let score = latest.score, let label = latest.label {
                Text("Latest: \(label) (\(score)/100)")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundColor(.white)
            } else {
                Text("Latest: No scored day yet")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))
            }
        }
        .padding(16)
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.10), lineWidth: 1))
    }

    private func smallStatCard(title: String, value: String, subtitle: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Spacer()
            }

            Text(title)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundColor(.white.opacity(0.65))

            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundColor(.white)

            Text(subtitle)
                .font(.system(.footnote, design: .rounded))
                .foregroundColor(.white.opacity(0.55))
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.10), lineWidth: 1))
    }

    private func glassCard<Content: View>(title: String, trailingIcon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: trailingIcon)
                    .foregroundColor(.white.opacity(0.7))
            }
            Divider().overlay(.white.opacity(0.12))
            content()
        }
        .padding(16)
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.10), lineWidth: 1))
    }

    private func recentRow(_ p: RiskPoint) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(p.date, formatter: DateFormatter.simpleDate)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundColor(.white)
                Text("Steps: \(p.steps.formatted())")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }
            Spacer()
            if let score = p.score, let label = p.label {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(score)/100")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundColor(.white)
                    Text(label)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("No data")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundColor(.white.opacity(0.8))
                    Text("Missing")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .padding(12)
        .background(.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
    }

    private func deltaText(_ d: Int) -> String {
        if d > 0 { return "+\(d)" }
        return "\(d)"
    }

    // Chart
    @ViewBuilder
    private func riskChart(points: [RiskPoint]) -> some View {
        #if canImport(Charts)
        if points.isEmpty {
            VStack {
                Spacer()
                Text("No scored points to plot.")
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
            }
        } else {
            Chart {
                ForEach(points) { p in
                    if let score = p.score {
                        LineMark(x: .value("Day", p.date), y: .value("Risk", score))
                        PointMark(x: .value("Day", p.date), y: .value("Risk", score))
                    }
                }
            }
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                    AxisValueLabel().foregroundStyle(Color.white.opacity(0.55))
                }
            }
            .chartYAxis {
                AxisMarks(values: [0,25,50,75,100]) { _ in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                    AxisValueLabel().foregroundStyle(Color.white.opacity(0.55))
                }
            }
        }
        #else
        let vals = points.compactMap { $0.score }.map { Double($0) }
        if vals.isEmpty {
            VStack {
                Spacer()
                Text("No scored points to plot.")
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
            }
        } else {
            SimpleLineChart(values: vals)
        }
        #endif
    }
}

// Simple fallback chart
private struct SimpleLineChart: View {
    let values: [Double]
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let maxV = max(values.max() ?? 1, 1)
            let minV = min(values.min() ?? 0, 0)
            let range = max(maxV - minV, 1)

            ZStack {
                VStack {
                    ForEach(0..<5) { _ in
                        Rectangle().fill(Color.white.opacity(0.02)).frame(height: 1)
                        Spacer()
                    }
                }
                .padding(.vertical, 8)

                Path { path in
                    guard values.count >= 2 else { return }
                    for i in values.indices {
                        let x = w * CGFloat(Double(i) / Double(values.count - 1))
                        let yNorm = (values[i] - minV) / range
                        let y = h * (1 - CGFloat(yNorm))
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(Color.green.opacity(0.95), lineWidth: 2)
                .shadow(color: Color.green.opacity(0.15), radius: 6, x: 0, y: 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

// Minimal date formatter used here (avoids redeclaring your helper)
private extension DateFormatter {
    static var simpleDate: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .long
        return f
    }
}

// Preview - uses empty steps to avoid Step ambuity in your project.
// If you want mock data in preview, tell me the exact Step initializer and I will update.
struct TrendsView_Previews: PreviewProvider {
    static var previews: some View {
        TrendsView(steps: [])
            .preferredColorScheme(.dark)
    }
}
