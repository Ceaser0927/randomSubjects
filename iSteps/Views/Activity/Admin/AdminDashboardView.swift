import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Charts
import UniformTypeIdentifiers
import libxlsxwriter

// MARK: - Models

struct ParticipantItem: Identifiable {
    let id: String      // uid
    let display: String
    let email: String
    let updatedAt: Date?
}

struct DailyRow: Identifiable {
    let id: String // "yyyy-MM-dd"

    let dateId: String
    let steps: Int?
    let sleepHours: Double?
    let hrvSDNNms: Double?
    let restingHRbpm: Double?
    let activeEnergyKcal: Double?

    let heartRateAvg: Double?
    let heartRateMin: Double?
    let heartRateMax: Double?
    let bloodOxygenAvg: Double?

    let hasHeartRate: Bool?
    let hasOxygen: Bool?

    let validDay: Bool?
    let syncedAt: Date?

    static func from(_ data: [String: Any], fallbackId: String) -> DailyRow {
        let dateId = (data["date"] as? String) ?? fallbackId

        let steps = data["steps"] as? Int
        let sleepHours = data["sleepHours"] as? Double
        let hrv = data["hrvSDNN_ms"] as? Double
        let rhr = data["restingHR_bpm"] as? Double
        let energy = data["activeEnergyKcal"] as? Double

        let heartRateAvg = data["heartRateAvg"] as? Double
        let heartRateMin = data["heartRateMin"] as? Double
        let heartRateMax = data["heartRateMax"] as? Double
        let bloodOxygenAvg = data["bloodOxygenAvg"] as? Double

        let hasHeartRate = data["hasHeartRate"] as? Bool
        let hasOxygen = data["hasOxygen"] as? Bool

        let validDay = data["validDay"] as? Bool

        let syncedAt: Date?
        if let ts = data["syncedAt"] as? Timestamp {
            syncedAt = ts.dateValue()
        } else {
            syncedAt = nil
        }

        return DailyRow(
            id: dateId,
            dateId: dateId,
            steps: steps,
            sleepHours: sleepHours,
            hrvSDNNms: hrv,
            restingHRbpm: rhr,
            activeEnergyKcal: energy,
            heartRateAvg: heartRateAvg,
            heartRateMin: heartRateMin,
            heartRateMax: heartRateMax,
            bloodOxygenAvg: bloodOxygenAvg,
            hasHeartRate: hasHeartRate,
            hasOxygen: hasOxygen,
            validDay: validDay,
            syncedAt: syncedAt
        )
    }
}

struct SleepNightlyRow: Identifiable {
    let id: String
    let sleepKey: String
    let anchorDateLocal: String
    let respiratoryRateAvg: Double?
    let asleepMin: Int?
    let awakeMin: Int?
    let coreMin: Int?
    let deepMin: Int?
    let remMin: Int?
    let hasStages: Bool?
    let startTimeUTC: Double?
    let endTimeUTC: Double?
    let createdAt: Date?

    static func from(_ data: [String: Any], fallbackId: String) -> SleepNightlyRow {
        let sleepKey = (data["sleepKey"] as? String) ?? fallbackId
        let anchorDateLocal = (data["anchorDateLocal"] as? String) ?? ""
        let respiratoryRateAvg = data["respiratoryRateAvg"] as? Double
        let asleepMin = data["asleepMin"] as? Int
        let awakeMin = data["awakeMin"] as? Int
        let coreMin = data["coreMin"] as? Int
        let deepMin = data["deepMin"] as? Int
        let remMin = data["remMin"] as? Int
        let hasStages = data["hasStages"] as? Bool
        let startTimeUTC = data["startTimeUTC"] as? Double
        let endTimeUTC = data["endTimeUTC"] as? Double

        let createdAt: Date?
        if let ts = data["createdAt"] as? Timestamp {
            createdAt = ts.dateValue()
        } else {
            createdAt = nil
        }

        return SleepNightlyRow(
            id: sleepKey,
            sleepKey: sleepKey,
            anchorDateLocal: anchorDateLocal,
            respiratoryRateAvg: respiratoryRateAvg,
            asleepMin: asleepMin,
            awakeMin: awakeMin,
            coreMin: coreMin,
            deepMin: deepMin,
            remMin: remMin,
            hasStages: hasStages,
            startTimeUTC: startTimeUTC,
            endTimeUTC: endTimeUTC,
            createdAt: createdAt
        )
    }
}

// MARK: - Metric selection

enum AdminMetric: String, CaseIterable, Identifiable {
    case steps = "Steps"
    case sleep = "Sleep"
    case hrv = "HRV SDNN"
    case rhr = "Resting HR"
    case heartRate = "Heart Rate"
    case respiratory = "Respiratory"
    case oxygen = "Blood Oxygen"
    case energy = "Active Energy"
    case all = "All (Normalized)"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .steps: return "figure.walk"
        case .sleep: return "bed.double"
        case .hrv: return "waveform.path.ecg"
        case .rhr: return "heart"
        case .heartRate: return "heart.text.square"
        case .respiratory: return "lungs.fill"
        case .oxygen: return "drop.fill"
        case .energy: return "flame"
        case .all: return "chart.xyaxis.line"
        }
    }
}

// MARK: - View

struct AdminDashboardView: View {

    @EnvironmentObject private var session: EmailAuthenticationController

    private var pilotBackground: some View {
        LinearGradient(
            colors: [
                Color.black,
                Color(red: 0.07, green: 0.08, blue: 0.12),
                Color(red: 0.10, green: 0.07, blue: 0.16)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @State private var participants: [ParticipantItem] = []
    @State private var selectedUID: String? = nil

    @State private var rangeDays: Int = 14

    // Raw loaded data
    @State private var allDailyRows: [DailyRow] = []
    @State private var allSleepRows: [SleepNightlyRow] = []

    // Filtered data for current range
    @State private var dailyRows: [DailyRow] = []
    @State private var sleepRows: [SleepNightlyRow] = []

    @State private var isLoading: Bool = false
    @State private var errorText: String? = nil

    @State private var selectedMetric: AdminMetric = .steps

    @State private var exportURL: URL? = nil
    @State private var showShare: Bool = false

    var body: some View {
        NavigationView {
            ZStack {
                pilotBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {

                        headerCard
                        selectorCard

                        if isLoading {
                            glassCard(title: "Loading", trailingIcon: "hourglass") {
                                HStack(spacing: 10) {
                                    ProgressView()
                                    Text("Fetching participants / study data…")
                                        .font(.system(.subheadline, design: .rounded))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            }
                        }

                        if let errorText {
                            glassCard(title: "Error", trailingIcon: "exclamationmark.triangle") {
                                Text(errorText)
                                    .font(.system(.footnote, design: .rounded))
                                    .foregroundColor(.white.opacity(0.75))
                            }
                        }

                        if let latest = latestDailyRow {
                            latestSummaryCard(latest)
                        }

                        trendsCard
                        exportCard

                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 90)
                }
            }
            .navigationTitle("Admin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        do {
                            try Auth.auth().signOut()
                            session.isLogin = false
                        } catch {
                            errorText = "Logout failed: \(error.localizedDescription)"
                        }
                    } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .accessibilityLabel("Logout")
                }
            }
            .onAppear { reloadAll() }
            .sheet(isPresented: $showShare) {
                if let exportURL {
                    ShareSheet(activityItems: [exportURL])
                }
            }
        }
    }

    // MARK: - Derived data

    private var latestDailyRow: DailyRow? {
        dailyRows.sorted(by: { $0.dateId > $1.dateId }).first
    }

    private var rangeCutoffDate: Date? {
        guard let latest = allDailyRows.compactMap({ Self.parseDateId($0.dateId) }).max() else {
            return nil
        }
        return Calendar.current.date(byAdding: .day, value: -(rangeDays - 1), to: latest)
    }

    private func respiratoryFor(dateId: String) -> Double? {
        sleepRows.first(where: { $0.anchorDateLocal == dateId })?.respiratoryRateAvg
    }

    private func latestRespiratoryForSummary(latestDateId: String) -> Double? {
        if let sameDay = respiratoryFor(dateId: latestDateId) {
            return sameDay
        }
        return sleepRows
            .sorted(by: { $0.anchorDateLocal > $1.anchorDateLocal })
            .first?.respiratoryRateAvg
    }
    private func heartRateSummaryText(_ row: DailyRow) -> String {
        let avg = row.heartRateAvg.map { String(format: "%.1f", $0) } ?? "—"
        let min = row.heartRateMin.map { String(format: "%.0f", $0) } ?? "—"
        let max = row.heartRateMax.map { String(format: "%.0f", $0) } ?? "—"
        return "\(avg) / \(min) / \(max)"
    }

    // MARK: - Cards

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .padding(10)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Admin Dashboard")
                        .font(.system(.headline, design: .rounded).weight(.semibold))
                        .foregroundColor(.white)
                    Text("Select participant • Review trends • Export study data")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(.white.opacity(0.65))
                }

                Spacer()

                Text("RESEARCH")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundColor(Color.white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
            }

            Divider().overlay(Color.white.opacity(0.12))

            HStack {
                Text("Signed in admin")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                Text(Auth.auth().currentUser?.email ?? "Unknown")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .minimumScaleFactor(0.85)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func participantLabel(for participant: ParticipantItem) -> String {
        let cleanEmail = participant.email.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanEmail.isEmpty { return cleanEmail }

        let cleanDisplay = participant.display.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanDisplay.isEmpty, cleanDisplay != participant.id { return cleanDisplay }

        return participant.id
    }

    private var selectedParticipantDisplay: String {
        if let uid = selectedUID, let p = participants.first(where: { $0.id == uid }) {
            return participantLabel(for: p)
        }
        if let first = participants.first {
            return participantLabel(for: first)
        }
        return "Select"
    }

    private var selectorCard: some View {
        glassCard(title: "Participant Selector", trailingIcon: "person.3") {
            VStack(spacing: 12) {

                if participants.isEmpty {
                    Text("No participants found yet.\n(Participant needs to login + tap Upload Now at least once.)")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundColor(.white.opacity(0.65))
                } else {
                    HStack {
                        Text("User")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundColor(.white)

                        Spacer()

                        Menu {
                            ForEach(participants) { p in
                                Button {
                                    selectedUID = p.id
                                    reloadParticipantData()
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(participantLabel(for: p))
                                        if p.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            Text(p.id)
                                                .font(.caption)
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(selectedParticipantDisplay)
                                    .foregroundColor(.accentColor)
                                Image(systemName: "chevron.up.chevron.down")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }

                    if let uid = selectedUID,
                       let p = participants.first(where: { $0.id == uid }),
                       p.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Email is unavailable for this participant until they log in again and refresh their admin index. Using UID for selection now.")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                HStack {
                    Text("Range")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundColor(.white)
                    Spacer()

                    Picker("", selection: $rangeDays) {
                        Text("Last 7 days").tag(7)
                        Text("Last 14 days").tag(14)
                        Text("Last 30 days").tag(30)
                        Text("Last 90 days").tag(90)
                    }
                    .pickerStyle(.menu)
                    .onChange(of: rangeDays) { _ in
                        applyRangeFilter()
                    }
                }

                HStack {
                    Text("Loaded")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(dailyRows.count) daily • \(sleepRows.count) nightly")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.08))
                        .clipShape(Capsule())
                }

                HStack(spacing: 12) {
                    Button {
                        reloadAll()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Refresh")
                        }
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.08))
                        .clipShape(Capsule())
                    }
                    .foregroundColor(.white)

                    Spacer()

                    if let uid = selectedUID, let p = participants.first(where: { $0.id == uid }) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(participantLabel(for: p))
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .foregroundColor(.white.opacity(0.85))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .minimumScaleFactor(0.85)

                            if p.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(p.id)
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundColor(.white.opacity(0.55))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.08))
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private func latestSummaryCard(_ latest: DailyRow) -> some View {
        let respiratory = latestRespiratoryForSummary(latestDateId: latest.dateId)

        return glassCard(title: "Latest Summary", trailingIcon: "doc.plaintext") {
            VStack(spacing: 10) {
                statusRow(title: "Date", value: latest.dateId, valueColor: .white.opacity(0.9), icon: "calendar")
                statusRow(title: "Steps", value: latest.steps.map(String.init) ?? "—", valueColor: .white.opacity(0.9), icon: "figure.walk")
                statusRow(title: "Sleep (h)", value: latest.sleepHours.map { String(format: "%.2f", $0) } ?? "—", valueColor: .white.opacity(0.9), icon: "bed.double")
                statusRow(title: "HRV SDNN (ms)", value: latest.hrvSDNNms.map { String(format: "%.2f", $0) } ?? "—", valueColor: .white.opacity(0.9), icon: "waveform.path.ecg")
                statusRow(title: "Resting HR (bpm)", value: latest.restingHRbpm.map { String(format: "%.0f", $0) } ?? "—", valueColor: .white.opacity(0.9), icon: "heart")
//                statusRow(title: "Heart Rate Avg (bpm)", value: latest.heartRateAvg.map { String(format: "%.1f", $0) } ?? "—", valueColor: .white.opacity(0.9), icon: "heart.text.square")
//                statusRow(title: "Heart Rate Min (bpm)", value: latest.heartRateMin.map { String(format: "%.0f", $0) } ?? "—", valueColor: .white.opacity(0.9), icon: "arrow.down.heart")
//                statusRow(title: "Heart Rate Max (bpm)", value: latest.heartRateMax.map { String(format: "%.0f", $0) } ?? "—", valueColor: .white.opacity(0.9), icon: "arrow.up.heart")
                statusRow(
                    title: "Heart Rate (avg / min / max)",
                    value: heartRateSummaryText(latest),
                    valueColor: .white.opacity(0.9),
                    icon: "heart.text.square"
                )
                statusRow(title: "Respiratory Rate", value: respiratory.map { String(format: "%.2f", $0) } ?? "—", valueColor: .white.opacity(0.9), icon: "lungs.fill")
                statusRow(title: "Blood Oxygen (%)", value: latest.bloodOxygenAvg.map { String(format: "%.1f", $0) } ?? "—", valueColor: .white.opacity(0.9), icon: "drop.fill")
                statusRow(title: "Active Energy (kcal)", value: latest.activeEnergyKcal.map { String(format: "%.1f", $0) } ?? "—", valueColor: .white.opacity(0.9), icon: "flame")

                Divider().overlay(.white.opacity(0.12))

                HStack {
                    Text("validDay")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Text((latest.validDay ?? false) ? "true" : "false")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundColor((latest.validDay ?? false) ? .green.opacity(0.9) : .orange.opacity(0.95))
                }

                HStack {
                    Text("syncedAt")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Text(latest.syncedAt.map(formatDateTime) ?? "—")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundColor(.white.opacity(0.75))
                }
            }
        }
    }

    // MARK: - Trends

    private var trendsCard: some View {
        glassCard(title: "Trends", trailingIcon: "chart.xyaxis.line") {
            VStack(alignment: .leading, spacing: 12) {

                if dailyRows.isEmpty && sleepRows.isEmpty {
                    Text("No study data yet for selected participant.")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundColor(.white.opacity(0.65))
                } else {

                    HStack {
                        Image(systemName: selectedMetric.systemImage)
                            .foregroundColor(.white.opacity(0.85))
                        Text("Metric")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundColor(.white)
                        Spacer()

                        Picker("", selection: $selectedMetric) {
                            ForEach(AdminMetric.allCases) { m in
                                Text(m.rawValue).tag(m)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    trendsChartView()
                        .frame(height: 220)
                        .padding(10)
                        .background(.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(.white.opacity(0.08), lineWidth: 1)
                        )

                    if selectedMetric == .all {
                        Text("All series are normalized to 0–1 for comparability (different units are not directly comparable).")
                            .font(.system(.footnote, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
        }
    }

    struct ChartPoint: Identifiable {
        let id = UUID()
        let dateId: String
        let value: Double
        let series: String

        var date: Date { AdminDashboardView.parseDateId(dateId) ?? Date() }
    }

    private func trendsChartView() -> some View {
        let points = buildTrendPoints(metric: selectedMetric)

        return Chart(points.sorted(by: { $0.date < $1.date })) { p in
            LineMark(
                x: .value("Date", p.date),
                y: .value("Value", p.value)
            )
            .foregroundStyle(by: .value("Series", p.series))

            PointMark(
                x: .value("Date", p.date),
                y: .value("Value", p.value)
            )
            .foregroundStyle(by: .value("Series", p.series))
        }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
        .chartYAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
        .chartLegend(.visible)
    }

    private func buildTrendPoints(metric: AdminMetric) -> [ChartPoint] {
        let dailySorted = dailyRows.sorted(by: { $0.dateId < $1.dateId })
        let sleepSorted = sleepRows.sorted(by: { $0.anchorDateLocal < $1.anchorDateLocal })

        switch metric {
        case .steps:
            return dailySorted.compactMap { r in
                guard let v = r.steps else { return nil }
                return ChartPoint(dateId: r.dateId, value: Double(v), series: "Steps")
            }

        case .sleep:
            return dailySorted.compactMap { r in
                guard let v = r.sleepHours else { return nil }
                return ChartPoint(dateId: r.dateId, value: v, series: "Sleep Hours")
            }

        case .hrv:
            return dailySorted.compactMap { r in
                guard let v = r.hrvSDNNms else { return nil }
                return ChartPoint(dateId: r.dateId, value: v, series: "HRV SDNN")
            }

        case .rhr:
            return dailySorted.compactMap { r in
                guard let v = r.restingHRbpm else { return nil }
                return ChartPoint(dateId: r.dateId, value: v, series: "Resting HR")
            }

        case .heartRate:
            return dailySorted.compactMap { r in
                guard let v = r.heartRateAvg else { return nil }
                return ChartPoint(dateId: r.dateId, value: v, series: "Heart Rate")
            }

        case .respiratory:
            return sleepSorted.compactMap { r in
                guard !r.anchorDateLocal.isEmpty, let v = r.respiratoryRateAvg else { return nil }
                return ChartPoint(dateId: r.anchorDateLocal, value: v, series: "Respiratory")
            }

        case .oxygen:
            return dailySorted.compactMap { r in
                guard let v = r.bloodOxygenAvg else { return nil }
                return ChartPoint(dateId: r.dateId, value: v, series: "Blood Oxygen")
            }

        case .energy:
            return dailySorted.compactMap { r in
                guard let v = r.activeEnergyKcal else { return nil }
                return ChartPoint(dateId: r.dateId, value: v, series: "Active Energy")
            }

        case .all:
            func normalize(_ series: [(String, Double)]) -> [(String, Double)] {
                guard let minV = series.map(\.1).min(),
                      let maxV = series.map(\.1).max() else { return [] }
                guard maxV > minV else {
                    return series.map { ($0.0, 0.0) }
                }
                return series.map { ($0.0, ($0.1 - minV) / (maxV - minV)) }
            }

            let stepsRaw: [(String, Double)] = dailySorted.compactMap { r in
                guard let v = r.steps else { return nil }
                return (r.dateId, Double(v))
            }

            let sleepRaw: [(String, Double)] = dailySorted.compactMap { r in
                guard let v = r.sleepHours else { return nil }
                return (r.dateId, v)
            }

            let hrvRaw: [(String, Double)] = dailySorted.compactMap { r in
                guard let v = r.hrvSDNNms else { return nil }
                return (r.dateId, v)
            }

            let rhrRaw: [(String, Double)] = dailySorted.compactMap { r in
                guard let v = r.restingHRbpm else { return nil }
                return (r.dateId, v)
            }

            let hrRaw: [(String, Double)] = dailySorted.compactMap { r in
                guard let v = r.heartRateAvg else { return nil }
                return (r.dateId, v)
            }

            let oxygenRaw: [(String, Double)] = dailySorted.compactMap { r in
                guard let v = r.bloodOxygenAvg else { return nil }
                return (r.dateId, v)
            }

            let energyRaw: [(String, Double)] = dailySorted.compactMap { r in
                guard let v = r.activeEnergyKcal else { return nil }
                return (r.dateId, v)
            }

            let respiratoryRaw: [(String, Double)] = sleepSorted.compactMap { r in
                guard !r.anchorDateLocal.isEmpty, let v = r.respiratoryRateAvg else { return nil }
                return (r.anchorDateLocal, v)
            }

            let steps = normalize(stepsRaw).map { ChartPoint(dateId: $0.0, value: $0.1, series: "Steps") }
            let sleep = normalize(sleepRaw).map { ChartPoint(dateId: $0.0, value: $0.1, series: "Sleep") }
            let hrv = normalize(hrvRaw).map { ChartPoint(dateId: $0.0, value: $0.1, series: "HRV") }
            let rhr = normalize(rhrRaw).map { ChartPoint(dateId: $0.0, value: $0.1, series: "RHR") }
            let hr = normalize(hrRaw).map { ChartPoint(dateId: $0.0, value: $0.1, series: "Heart Rate") }
            let respiratory = normalize(respiratoryRaw).map { ChartPoint(dateId: $0.0, value: $0.1, series: "Respiratory") }
            let oxygen = normalize(oxygenRaw).map { ChartPoint(dateId: $0.0, value: $0.1, series: "Oxygen") }
            let energy = normalize(energyRaw).map { ChartPoint(dateId: $0.0, value: $0.1, series: "Energy") }

            return steps + sleep + hrv + rhr + hr + respiratory + oxygen + energy
        }
    }

    // MARK: - Export

    private var exportCard: some View {
        glassCard(title: "Export", trailingIcon: "square.and.arrow.up") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Export the selected participant’s filtered range data, including the new heart rate, respiratory, and blood oxygen fields.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))

                Menu {
                    Button {
                        exportCSV()
                    } label: {
                        Label("Download CSV", systemImage: "doc.plaintext")
                    }

                    Button {
                        exportJSONFull()
                    } label: {
                        Label("Download JSON", systemImage: "curlybraces")
                    }

                    Button {
                        exportXLSX()
                    } label: {
                        Label("Download Excel (.xlsx)", systemImage: "tablecells")
                    }
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text("Download")
                    }
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                }
                .foregroundColor(.white)
                .disabled((dailyRows.isEmpty && sleepRows.isEmpty) || selectedUID == nil)

                if let exportURL {
                    Text("Ready: \(exportURL.lastPathComponent)")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))

                    Button {
                        showShare = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share…")
                        }
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }

    // MARK: - Firestore load

    private func reloadAll() {
        errorText = nil
        exportURL = nil
        dailyRows = []
        sleepRows = []
        allDailyRows = []
        allSleepRows = []
        loadParticipantsThenData()
    }

    private func loadParticipantsThenData() {
        isLoading = true
        let db = Firestore.firestore()
        let group = DispatchGroup()

        var participantDocs: [QueryDocumentSnapshot] = []
        var adminIndexDocs: [QueryDocumentSnapshot] = []
        var loadError: String?

        group.enter()
        db.collection("participants")
            .limit(to: 300)
            .getDocuments { snap, err in
                if let err {
                    loadError = "Load participants failed: \(err.localizedDescription)"
                } else {
                    participantDocs = snap?.documents ?? []
                }
                group.leave()
            }

        group.enter()
        db.collection("admin_participant_index")
            .limit(to: 300)
            .getDocuments { snap, err in
                if let err {
                    loadError = loadError ?? "Load participant index failed: \(err.localizedDescription)"
                } else {
                    adminIndexDocs = snap?.documents ?? []
                }
                group.leave()
            }

        group.notify(queue: .main) {
            if let loadError {
                isLoading = false
                errorText = loadError
                return
            }

            let participantMap = Dictionary(uniqueKeysWithValues: participantDocs.map { ($0.documentID, $0.data()) })
            let adminIndexMap = Dictionary(uniqueKeysWithValues: adminIndexDocs.map { ($0.documentID, $0.data()) })
            let allUIDs = Set(participantMap.keys).union(adminIndexMap.keys)

            let list: [ParticipantItem] = allUIDs.map { uid in
                let participantData = participantMap[uid] ?? [:]
                let adminData = adminIndexMap[uid] ?? [:]

                let email = (adminData["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let display = ((adminData["display"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? (email.isEmpty ? uid : email)

                let adminUpdatedAt = (adminData["updatedAt"] as? Timestamp)?.dateValue()
                let participantUpdatedAt = (participantData["updatedAt"] as? Timestamp)?.dateValue()
                let updatedAt = max(adminUpdatedAt ?? .distantPast, participantUpdatedAt ?? .distantPast)

                return ParticipantItem(
                    id: uid,
                    display: display,
                    email: email,
                    updatedAt: updatedAt == .distantPast ? nil : updatedAt
                )
            }
            .sorted { lhs, rhs in
                switch (lhs.updatedAt, rhs.updatedAt) {
                case let (l?, r?):
                    return l > r
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.id < rhs.id
                }
            }

            self.participants = list

            if let selectedUID, list.contains(where: { $0.id == selectedUID }) == false {
                self.selectedUID = nil
            }

            if self.selectedUID == nil {
                self.selectedUID = list.first?.id
            }

            self.reloadParticipantData()
        }
    }

    private func reloadParticipantData() {
        guard let uid = selectedUID else {
            isLoading = false
            return
        }

        isLoading = true
        errorText = nil
        exportURL = nil
        dailyRows = []
        sleepRows = []
        allDailyRows = []
        allSleepRows = []

        let db = Firestore.firestore()
        let participantRef = db.collection("participants").document(uid)
        let group = DispatchGroup()

        var loadError: String?

        group.enter()
        participantRef.collection("daily")
            .order(by: "date", descending: false)
            .getDocuments { snap, err in
                if let err {
                    loadError = "Failed to load daily data: \(err.localizedDescription)"
                } else {
                    self.allDailyRows = (snap?.documents ?? []).map { d in
                        DailyRow.from(d.data(), fallbackId: d.documentID)
                    }
                }
                group.leave()
            }

        group.enter()
        participantRef.collection("sleep_nightly")
            .getDocuments { snap, err in
                if let err {
                    loadError = loadError ?? "Failed to load sleep_nightly data: \(err.localizedDescription)"
                } else {
                    self.allSleepRows = (snap?.documents ?? []).map { d in
                        SleepNightlyRow.from(d.data(), fallbackId: d.documentID)
                    }
                }
                group.leave()
            }

        group.notify(queue: .main) {
            self.isLoading = false
            if let loadError {
                self.errorText = loadError
                return
            }
            self.applyRangeFilter()
        }
    }

    private func applyRangeFilter() {
        exportURL = nil

        guard let cutoff = rangeCutoffDate else {
            dailyRows = allDailyRows
            sleepRows = allSleepRows
            return
        }

        dailyRows = allDailyRows.filter { row in
            guard let date = Self.parseDateId(row.dateId) else { return false }
            return date >= cutoff
        }

        sleepRows = allSleepRows.filter { row in
            guard let date = Self.parseDateId(row.anchorDateLocal) else { return false }
            return date >= cutoff
        }
    }

    private func exportCSV() {
        guard let uid = selectedUID else { return }
        let display = participants.first(where: { $0.id == uid }).map(participantLabel(for:)) ?? uid

        let rows = dailyRows.sorted(by: { $0.dateId < $1.dateId })

        var csv = "date,steps,sleepHours,hrvSDNN_ms,restingHR_bpm,heartRateAvg,heartRateMin,heartRateMax,bloodOxygenAvg,respiratoryRateAvg,activeEnergyKcal,validDay,syncedAt\n"

        for r in rows {
            let steps = r.steps.map(String.init) ?? ""
            let sleep = r.sleepHours.map { String(format: "%.4f", $0) } ?? ""
            let hrv = r.hrvSDNNms.map { String(format: "%.6f", $0) } ?? ""
            let rhr = r.restingHRbpm.map { String(format: "%.2f", $0) } ?? ""
            let hrAvg = r.heartRateAvg.map { String(format: "%.6f", $0) } ?? ""
            let hrMin = r.heartRateMin.map { String(format: "%.6f", $0) } ?? ""
            let hrMax = r.heartRateMax.map { String(format: "%.6f", $0) } ?? ""
            let oxygen = r.bloodOxygenAvg.map { String(format: "%.6f", $0) } ?? ""
            let respiratory = respiratoryFor(dateId: r.dateId).map { String(format: "%.6f", $0) } ?? ""
            let energy = r.activeEnergyKcal.map { String(format: "%.6f", $0) } ?? ""
            let valid = r.validDay.map { $0 ? "true" : "false" } ?? ""
            let synced = r.syncedAt.map(iso8601) ?? ""

            csv += "\(r.dateId),\(steps),\(sleep),\(hrv),\(rhr),\(hrAvg),\(hrMin),\(hrMax),\(oxygen),\(respiratory),\(energy),\(valid),\(synced)\n"
        }

        let safeName = display
            .replacingOccurrences(of: "@", with: "_")
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        let fileName = "pilot_export_\(safeName)_\(rangeDays)d.csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try csv.data(using: .utf8)?.write(to: url, options: .atomic)
            exportURL = url
            showShare = true
        } catch {
            errorText = "Export failed: \(error.localizedDescription)"
        }
    }

    // MARK: - UI helpers

    private func glassCard<Content: View>(
        title: String,
        trailingIcon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
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
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func statusRow(title: String, value: String, valueColor: Color, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 28, height: 28)
                .background(.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundColor(.white)

            Spacer()

            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundColor(valueColor)
        }
        .padding(12)
        .background(.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func formatDateTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }

    private static func parseDateId(_ s: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }

    private func iso8601(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: d)
    }

    private func exportJSONFull() {
        guard let uid = selectedUID else { return }
        let display = participants.first(where: { $0.id == uid }).map(participantLabel(for:)) ?? uid

        isLoading = true
        errorText = nil

        let payload: [String: Any] = [
            "uid": uid,
            "exportedAt": iso8601(Date()),
            "rangeDays": rangeDays,
            "daily": dailyRows.sorted(by: { $0.dateId < $1.dateId }).map { row in
                [
                    "date": row.dateId,
                    "steps": row.steps as Any,
                    "sleepHours": row.sleepHours as Any,
                    "hrvSDNN_ms": row.hrvSDNNms as Any,
                    "restingHR_bpm": row.restingHRbpm as Any,
                    "heartRateAvg": row.heartRateAvg as Any,
                    "heartRateMin": row.heartRateMin as Any,
                    "heartRateMax": row.heartRateMax as Any,
                    "bloodOxygenAvg": row.bloodOxygenAvg as Any,
                    "hasHeartRate": row.hasHeartRate as Any,
                    "hasOxygen": row.hasOxygen as Any,
                    "activeEnergyKcal": row.activeEnergyKcal as Any,
                    "validDay": row.validDay as Any,
                    "syncedAt": row.syncedAt.map(iso8601) as Any
                ]
            },
            "sleep_nightly": sleepRows.sorted(by: { $0.anchorDateLocal < $1.anchorDateLocal }).map { row in
                [
                    "sleepKey": row.sleepKey,
                    "anchorDateLocal": row.anchorDateLocal,
                    "respiratoryRateAvg": row.respiratoryRateAvg as Any,
                    "asleepMin": row.asleepMin as Any,
                    "awakeMin": row.awakeMin as Any,
                    "coreMin": row.coreMin as Any,
                    "deepMin": row.deepMin as Any,
                    "remMin": row.remMin as Any,
                    "hasStages": row.hasStages as Any,
                    "startTimeUTC": row.startTimeUTC as Any,
                    "endTimeUTC": row.endTimeUTC as Any,
                    "createdAt": row.createdAt.map(iso8601) as Any
                ]
            }
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])

            let safeName = display
                .replacingOccurrences(of: "@", with: "_")
                .replacingOccurrences(of: ".", with: "_")
                .replacingOccurrences(of: " ", with: "_")

            let fileName = "pilot_export_full_\(safeName)_\(rangeDays)d.json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

            try data.write(to: url, options: .atomic)
            exportURL = url
            showShare = true
            isLoading = false
        } catch {
            isLoading = false
            errorText = "Export JSON failed: \(error.localizedDescription)"
        }
    }

    private func exportXLSX() {
        guard let uid = selectedUID else { return }
        let display = participants.first(where: { $0.id == uid }).map(participantLabel(for:)) ?? uid

        let daily = dailyRows.sorted(by: { $0.dateId < $1.dateId })
        let nightly = sleepRows.sorted(by: { $0.anchorDateLocal < $1.anchorDateLocal })

        let safeName = display
            .replacingOccurrences(of: "@", with: "_")
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        let fileName = "pilot_export_\(safeName)_\(rangeDays)d.xlsx"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let path = url.path

        guard let workbook = workbook_new(path) else {
            errorText = "Export Excel failed: workbook_new returned nil"
            return
        }

        let headerFormat = workbook_add_format(workbook)
        format_set_bold(headerFormat)

        // Daily sheet
        let dailySheet = workbook_add_worksheet(workbook, "Daily")
        let dailyHeaders = [
            "date",
            "steps",
            "sleepHours",
            "hrvSDNN_ms",
            "restingHR_bpm",
            "heartRateAvg",
            "heartRateMin",
            "heartRateMax",
            "bloodOxygenAvg",
            "respiratoryRateAvg",
            "activeEnergyKcal",
            "hasHeartRate",
            "hasOxygen",
            "validDay",
            "syncedAt"
        ]

        for (col, h) in dailyHeaders.enumerated() {
            worksheet_write_string(dailySheet, 0, lxw_col_t(col), h, headerFormat)
        }

        for (i, r) in daily.enumerated() {
            let row = lxw_row_t(i + 1)

            worksheet_write_string(dailySheet, row, 0, r.dateId, nil)

            if let v = r.steps { worksheet_write_number(dailySheet, row, 1, Double(v), nil) }
            if let v = r.sleepHours { worksheet_write_number(dailySheet, row, 2, v, nil) }
            if let v = r.hrvSDNNms { worksheet_write_number(dailySheet, row, 3, v, nil) }
            if let v = r.restingHRbpm { worksheet_write_number(dailySheet, row, 4, v, nil) }
            if let v = r.heartRateAvg { worksheet_write_number(dailySheet, row, 5, v, nil) }
            if let v = r.heartRateMin { worksheet_write_number(dailySheet, row, 6, v, nil) }
            if let v = r.heartRateMax { worksheet_write_number(dailySheet, row, 7, v, nil) }
            if let v = r.bloodOxygenAvg { worksheet_write_number(dailySheet, row, 8, v, nil) }

            if let v = respiratoryFor(dateId: r.dateId) {
                worksheet_write_number(dailySheet, row, 9, v, nil)
            }

            if let v = r.activeEnergyKcal { worksheet_write_number(dailySheet, row, 10, v, nil) }
            if let v = r.hasHeartRate { worksheet_write_string(dailySheet, row, 11, v ? "true" : "false", nil) }
            if let v = r.hasOxygen { worksheet_write_string(dailySheet, row, 12, v ? "true" : "false", nil) }
            if let v = r.validDay { worksheet_write_string(dailySheet, row, 13, v ? "true" : "false", nil) }
            if let d = r.syncedAt { worksheet_write_string(dailySheet, row, 14, iso8601(d), nil) }
        }

        // Sleep sheet
        let sleepSheet = workbook_add_worksheet(workbook, "SleepNightly")
        let sleepHeaders = [
            "anchorDateLocal",
            "sleepKey",
            "respiratoryRateAvg",
            "asleepMin",
            "awakeMin",
            "coreMin",
            "deepMin",
            "remMin",
            "hasStages",
            "startTimeUTC",
            "endTimeUTC",
            "createdAt"
        ]

        for (col, h) in sleepHeaders.enumerated() {
            worksheet_write_string(sleepSheet, 0, lxw_col_t(col), h, headerFormat)
        }

        for (i, r) in nightly.enumerated() {
            let row = lxw_row_t(i + 1)

            worksheet_write_string(sleepSheet, row, 0, r.anchorDateLocal, nil)
            worksheet_write_string(sleepSheet, row, 1, r.sleepKey, nil)

            if let v = r.respiratoryRateAvg { worksheet_write_number(sleepSheet, row, 2, v, nil) }
            if let v = r.asleepMin { worksheet_write_number(sleepSheet, row, 3, Double(v), nil) }
            if let v = r.awakeMin { worksheet_write_number(sleepSheet, row, 4, Double(v), nil) }
            if let v = r.coreMin { worksheet_write_number(sleepSheet, row, 5, Double(v), nil) }
            if let v = r.deepMin { worksheet_write_number(sleepSheet, row, 6, Double(v), nil) }
            if let v = r.remMin { worksheet_write_number(sleepSheet, row, 7, Double(v), nil) }
            if let v = r.hasStages { worksheet_write_string(sleepSheet, row, 8, v ? "true" : "false", nil) }
            if let v = r.startTimeUTC { worksheet_write_number(sleepSheet, row, 9, v, nil) }
            if let v = r.endTimeUTC { worksheet_write_number(sleepSheet, row, 10, v, nil) }
            if let d = r.createdAt { worksheet_write_string(sleepSheet, row, 11, iso8601(d), nil) }
        }

        worksheet_set_column(dailySheet, 0, 14, 16, nil)
        worksheet_set_column(sleepSheet, 0, 11, 16, nil)

        let result = workbook_close(workbook)
        if result != LXW_NO_ERROR {
            errorText = "Export Excel failed: workbook_close error code \(result)"
            return
        }

        exportURL = url
        showShare = true
    }
}

// MARK: - ShareSheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
