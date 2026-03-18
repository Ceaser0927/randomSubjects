import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Charts
import UniformTypeIdentifiers
import libxlsxwriter

// MARK: - Models

struct ParticipantItem: Identifiable {
    let id: String      // uid
    let display: String // email (or uid fallback)
    let email: String
    let updatedAt: Date?
}

struct DailyRow: Identifiable {
    // Use dateId as id
    let id: String // "yyyy-MM-dd"

    let dateId: String
    let steps: Int?
    let sleepHours: Double?
    let hrvSDNNms: Double?
    let restingHRbpm: Double?
    let activeEnergyKcal: Double?
    let validDay: Bool?
    let syncedAt: Date?

    static func from(_ data: [String: Any], fallbackId: String) -> DailyRow {
        let dateId = (data["date"] as? String) ?? fallbackId

        let steps = data["steps"] as? Int
        let sleepHours = data["sleepHours"] as? Double
        let hrv = data["hrvSDNN_ms"] as? Double
        let rhr = data["restingHR_bpm"] as? Double
        let energy = data["activeEnergyKcal"] as? Double
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
            validDay: validDay,
            syncedAt: syncedAt
        )
    }
}

// MARK: - Metric selection

enum AdminMetric: String, CaseIterable, Identifiable {
    case steps = "Steps"
    case sleep = "Sleep"
    case hrv = "HRV SDNN"
    case rhr = "Resting HR"
    case energy = "Active Energy"
    case all = "All (Normalized)"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .steps: return "figure.walk"
        case .sleep: return "bed.double"
        case .hrv: return "waveform.path.ecg"
        case .rhr: return "heart"
        case .energy: return "flame"
        case .all: return "chart.xyaxis.line"
        }
    }
}

// MARK: - View

struct AdminDashboardView: View {

    @EnvironmentObject private var session: EmailAuthenticationController

    // Same look & feel as pilot
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

    // Use plain Int to avoid Picker tag mismatch issues.
    @State private var rangeDays: Int = 14

    @State private var dailyRows: [DailyRow] = []
    @State private var isLoading: Bool = false
    @State private var errorText: String? = nil

    // Trend controls
    @State private var selectedMetric: AdminMetric = .steps

    // Export
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
                                    Text("Fetching participants / daily data…")
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

                        if let latest = dailyRows.sorted(by: { $0.dateId > $1.dateId }).first {
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
                if let exportURL { ShareSheet(activityItems: [exportURL]) }
            }
        }
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
                    Text("Select participant • Review trends • Export CSV")
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

    private var selectedParticipantDisplay: String {
        if let uid = selectedUID, let p = participants.first(where: { $0.id == uid }) {
            return p.display
        }
        return participants.first?.display ?? "Select"
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
                                    reloadDaily()
                                } label: {
                                    Text(p.display)
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
                        reloadDaily()
                    }
                }

                // Showing loaded count helps clarify why the UI may look unchanged if the user has
                // fewer docs than the selected range.
                HStack {
                    Text("Loaded")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(dailyRows.count) / \(rangeDays) days")
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
                        HStack { Image(systemName: "arrow.triangle.2.circlepath"); Text("Refresh") }
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.08))
                            .clipShape(Capsule())
                    }
                    .foregroundColor(.white)

                    Spacer()

                    if let uid = selectedUID, let p = participants.first(where: { $0.id == uid }) {
                        Text(p.display)
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundColor(.white.opacity(0.85))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.08))
                            .clipShape(Capsule())
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .minimumScaleFactor(0.85)
                    }
                }
            }
        }
    }

    private func latestSummaryCard(_ latest: DailyRow) -> some View {
        glassCard(title: "Latest Summary", trailingIcon: "doc.plaintext") {
            VStack(spacing: 10) {
                statusRow(title: "Date", value: latest.dateId, valueColor: .white.opacity(0.9), icon: "calendar")
                statusRow(title: "Steps", value: latest.steps.map(String.init) ?? "—", valueColor: .white.opacity(0.9), icon: "figure.walk")
                statusRow(title: "Sleep (h)", value: latest.sleepHours.map { String(format: "%.2f", $0) } ?? "—", valueColor: .white.opacity(0.9), icon: "bed.double")
                statusRow(title: "HRV SDNN (ms)", value: latest.hrvSDNNms.map { String(format: "%.2f", $0) } ?? "—", valueColor: .white.opacity(0.9), icon: "waveform.path.ecg")
                statusRow(title: "Resting HR (bpm)", value: latest.restingHRbpm.map { String(format: "%.0f", $0) } ?? "—", valueColor: .white.opacity(0.9), icon: "heart")
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

    // MARK: - Trends (single chart + dropdown)

    private var trendsCard: some View {
        glassCard(title: "Trends", trailingIcon: "chart.xyaxis.line") {
            VStack(alignment: .leading, spacing: 12) {

                if dailyRows.isEmpty {
                    Text("No daily data yet for selected participant.")
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
        let points = buildTrendPoints(metric: selectedMetric, rows: dailyRows)

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

    private func buildTrendPoints(metric: AdminMetric, rows: [DailyRow]) -> [ChartPoint] {
        let sorted = rows.sorted(by: { $0.dateId < $1.dateId })

        switch metric {
        case .steps:
            return sorted.compactMap { r in
                guard let v = r.steps else { return nil }
                return ChartPoint(dateId: r.dateId, value: Double(v), series: "Steps")
            }

        case .sleep:
            return sorted.compactMap { r in
                guard let v = r.sleepHours else { return nil }
                return ChartPoint(dateId: r.dateId, value: v, series: "Sleep Hours")
            }

        case .hrv:
            return sorted.compactMap { r in
                guard let v = r.hrvSDNNms else { return nil }
                return ChartPoint(dateId: r.dateId, value: v, series: "HRV SDNN")
            }

        case .rhr:
            return sorted.compactMap { r in
                guard let v = r.restingHRbpm else { return nil }
                return ChartPoint(dateId: r.dateId, value: v, series: "Resting HR")
            }

        case .energy:
            return sorted.compactMap { r in
                guard let v = r.activeEnergyKcal else { return nil }
                return ChartPoint(dateId: r.dateId, value: v, series: "Active Energy")
            }

        case .all:
            // Normalize each metric independently to 0–1 (min-max).
            func normalize(_ series: [(String, Double)]) -> [(String, Double)] {
                guard let minV = series.map(\.1).min(),
                      let maxV = series.map(\.1).max() else { return [] }
                guard maxV > minV else {
                    return series.map { ($0.0, 0.0) }
                }
                return series.map { ($0.0, ($0.1 - minV) / (maxV - minV)) }
            }

            let stepsRaw: [(String, Double)] = sorted.compactMap { r in
                guard let v = r.steps else { return nil }
                return (r.dateId, Double(v))
            }
            let sleepRaw: [(String, Double)] = sorted.compactMap { r in
                guard let v = r.sleepHours else { return nil }
                return (r.dateId, v)
            }
            let hrvRaw: [(String, Double)] = sorted.compactMap { r in
                guard let v = r.hrvSDNNms else { return nil }
                return (r.dateId, v)
            }
            let rhrRaw: [(String, Double)] = sorted.compactMap { r in
                guard let v = r.restingHRbpm else { return nil }
                return (r.dateId, v)
            }
            let energyRaw: [(String, Double)] = sorted.compactMap { r in
                guard let v = r.activeEnergyKcal else { return nil }
                return (r.dateId, v)
            }

            let steps = normalize(stepsRaw).map { ChartPoint(dateId: $0.0, value: $0.1, series: "Steps") }
            let sleep = normalize(sleepRaw).map { ChartPoint(dateId: $0.0, value: $0.1, series: "Sleep") }
            let hrv = normalize(hrvRaw).map { ChartPoint(dateId: $0.0, value: $0.1, series: "HRV") }
            let rhr = normalize(rhrRaw).map { ChartPoint(dateId: $0.0, value: $0.1, series: "RHR") }
            let energy = normalize(energyRaw).map { ChartPoint(dateId: $0.0, value: $0.1, series: "Energy") }

            return steps + sleep + hrv + rhr + energy
        }
    }

    // MARK: - Export CSV

    private var exportCard: some View {
        glassCard(title: "Export", trailingIcon: "square.and.arrow.up") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Export selected participant’s daily rows as CSV (Excel-compatible).")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))

//                Button {
//                    exportCSV()
//                } label: {
//                    HStack {
//                        Image(systemName: "doc.badge.plus")
//                        Text("Download CSV")
//                    }
//                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
//                    .padding(.horizontal, 14)
//                    .padding(.vertical, 8)
//                    .background(Color.white.opacity(0.08))
//                    .clipShape(Capsule())
//                }
                Menu {
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

                    // 可选：保留 CSV 也行
                    // Button { exportCSV() } label: { Label("Download CSV", systemImage: "doc.plaintext") }

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
                .disabled(dailyRows.isEmpty || selectedUID == nil)
                .foregroundColor(.white)
                .disabled(dailyRows.isEmpty || selectedUID == nil)

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
        loadParticipantsThenDaily()
    }

    private func loadParticipantsThenDaily() {
        isLoading = true
        let db = Firestore.firestore()

        db.collection("participants")
            .order(by: "updatedAt", descending: true)
            .limit(to: 300)
            .getDocuments { snap, err in
                if let err {
                    isLoading = false
                    errorText = "Load participants failed: \(err.localizedDescription)"
                    return
                }

                let list: [ParticipantItem] = (snap?.documents ?? []).map { d in
                    let data = d.data()
                    let email = data["email"] as? String ?? ""
                    let display = data["display"] as? String ?? (email.isEmpty ? d.documentID : email)

                    let updatedAt: Date?
                    if let ts = data["updatedAt"] as? Timestamp {
                        updatedAt = ts.dateValue()
                    } else {
                        updatedAt = nil
                    }

                    return ParticipantItem(
                        id: d.documentID,
                        display: display,
                        email: email,
                        updatedAt: updatedAt
                    )
                }

                self.participants = list

                if self.selectedUID == nil {
                    self.selectedUID = list.first?.id
                }

                self.reloadDaily()
            }
    }

    private func reloadDaily() {
        guard let uid = selectedUID else {
            isLoading = false
            return
        }

        isLoading = true
        errorText = nil
        exportURL = nil
        dailyRows = []

        let db = Firestore.firestore()

        db.collection("participants")
            .document(uid)
            .collection("daily")
            .order(by: "date", descending: true)
            .limit(to: rangeDays)
            .getDocuments { snap, err in
                isLoading = false
                if let err {
                    errorText = "Failed to load daily data: \(err.localizedDescription)"
                    return
                }

                self.dailyRows = (snap?.documents ?? []).map { d in
                    DailyRow.from(d.data(), fallbackId: d.documentID)
                }
            }
    }

    private func exportCSV() {
        guard let uid = selectedUID else { return }
        let display = participants.first(where: { $0.id == uid })?.display ?? uid

        let rows = dailyRows.sorted(by: { $0.dateId < $1.dateId })

        var csv = "date,steps,sleepHours,hrvSDNN_ms,restingHR_bpm,activeEnergyKcal,validDay,syncedAt\n"

        for r in rows {
            let steps = r.steps.map(String.init) ?? ""
            let sleep = r.sleepHours.map { String(format: "%.4f", $0) } ?? ""
            let hrv = r.hrvSDNNms.map { String(format: "%.6f", $0) } ?? ""
            let rhr = r.restingHRbpm.map { String(format: "%.2f", $0) } ?? ""
            let energy = r.activeEnergyKcal.map { String(format: "%.6f", $0) } ?? ""
            let valid = r.validDay.map { $0 ? "true" : "false" } ?? ""
            let synced = r.syncedAt.map(iso8601) ?? ""

            csv += "\(r.dateId),\(steps),\(sleep),\(hrv),\(rhr),\(energy),\(valid),\(synced)\n"
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

    // MARK: - UI helpers (same style)

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
        let display = participants.first(where: { $0.id == uid })?.display ?? uid

        isLoading = true
        errorText = nil

        let db = Firestore.firestore()
        let participantRef = db.collection("participants").document(uid)

        participantRef.getDocument { pSnap, pErr in
            if let pErr {
                isLoading = false
                errorText = "Load participant failed: \(pErr.localizedDescription)"
                return
            }

            let participantData = pSnap?.data() ?? [:]

            let group = DispatchGroup()

            var dailyDocs: [[String: Any]] = []
            var sleepDocs: [[String: Any]] = []

            // ---- daily (不 limit，导出完整) ----
            group.enter()
            participantRef.collection("daily")
                .order(by: "date", descending: false)
                .getDocuments { snap, err in
                    defer { group.leave() }
                    if let err { errorText = "Load daily failed: \(err.localizedDescription)"; return }

                    dailyDocs = (snap?.documents ?? []).map { d in
                        var obj = d.data()
                        obj["_id"] = d.documentID
                        // Timestamp -> ISO8601（可选）
                        obj = normalizeTimestamps(obj)
                        return obj
                    }
                }

            // ---- sleep_nightly (导出完整) ----
            group.enter()
            participantRef.collection("sleep_nightly")
                .getDocuments { snap, err in
                    defer { group.leave() }
                    if let err {
                        errorText = "Load sleep_nightly failed: \(err.localizedDescription)"
                        return
                    }

                    sleepDocs = (snap?.documents ?? []).map { d in
                        var obj = d.data()
                        obj["_id"] = d.documentID
                        obj = normalizeTimestamps(obj)
                        return obj
                    }
                }

            group.notify(queue: .main) {
                isLoading = false
                if let errorText, !errorText.isEmpty { return }

                let payload: [String: Any] = [
                    "uid": uid,
                    "exportedAt": iso8601(Date()),
                    "participant": normalizeTimestamps(participantData),
                    "daily": dailyDocs,
                    "sleep_nightly": sleepDocs
                ]

                do {
                    let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])

                    let safeName = display
                        .replacingOccurrences(of: "@", with: "_")
                        .replacingOccurrences(of: ".", with: "_")
                        .replacingOccurrences(of: " ", with: "_")

                    let fileName = "pilot_export_full_\(safeName).json"
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

                    try data.write(to: url, options: .atomic)
                    exportURL = url
                    showShare = true
                } catch {
                    errorText = "Export JSON failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func normalizeTimestamps(_ dict: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (k, v) in dict {
            if let ts = v as? Timestamp {
                out[k] = iso8601(ts.dateValue())
            } else if let sub = v as? [String: Any] {
                out[k] = normalizeTimestamps(sub)
            } else if let arr = v as? [Any] {
                out[k] = arr.map { item -> Any in
                    if let ts = item as? Timestamp { return iso8601(ts.dateValue()) }
                    if let sub = item as? [String: Any] { return normalizeTimestamps(sub) }
                    return item
                }
            } else {
                out[k] = v
            }
        }
        return out
    }
    private func exportXLSX() {
        guard let uid = selectedUID else { return }
        let display = participants.first(where: { $0.id == uid })?.display ?? uid
        let rows = dailyRows.sorted(by: { $0.dateId < $1.dateId })

        // 文件名
        let safeName = display
            .replacingOccurrences(of: "@", with: "_")
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        let fileName = "pilot_export_\(safeName)_\(rangeDays)d.xlsx"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        // libxlsxwriter 需要 file path 字符串
        let path = url.path

        // 创建 workbook / worksheet
        guard let workbook = workbook_new(path) else {
            errorText = "Export Excel failed: workbook_new returned nil"
            return
        }
        let worksheet = workbook_add_worksheet(workbook, "Daily")

        // 一些格式（可选）
        let headerFormat = workbook_add_format(workbook)
        format_set_bold(headerFormat)

        // Header
        let headers = [
            "date",
            "steps",
            "sleepHours",
            "hrvSDNN_ms",
            "restingHR_bpm",
            "activeEnergyKcal",
            "validDay",
            "syncedAt"
        ]

        for (col, h) in headers.enumerated() {
            worksheet_write_string(worksheet, 0, lxw_col_t(col), h, headerFormat)
        }

        // 内容
        for (i, r) in rows.enumerated() {
            let row = lxw_row_t(i + 1)

            // date（字符串）
            worksheet_write_string(worksheet, row, 0, r.dateId, nil)

            // steps（数字）
            if let v = r.steps {
                worksheet_write_number(worksheet, row, 1, Double(v), nil)
            }

            // sleepHours
            if let v = r.sleepHours {
                worksheet_write_number(worksheet, row, 2, v, nil)
            }

            // hrvSDNN_ms
            if let v = r.hrvSDNNms {
                worksheet_write_number(worksheet, row, 3, v, nil)
            }

            // restingHR_bpm
            if let v = r.restingHRbpm {
                worksheet_write_number(worksheet, row, 4, v, nil)
            }

            // activeEnergyKcal
            if let v = r.activeEnergyKcal {
                worksheet_write_number(worksheet, row, 5, v, nil)
            }

            // validDay（写成 true/false 字符串更直观）
            if let v = r.validDay {
                worksheet_write_string(worksheet, row, 6, v ? "true" : "false", nil)
            }

            // syncedAt（ISO8601 字符串）
            if let d = r.syncedAt {
                worksheet_write_string(worksheet, row, 7, iso8601(d), nil)
            }
        }

        // 可选：列宽好看一点
        worksheet_set_column(worksheet, 0, 0, 12, nil) // date
        worksheet_set_column(worksheet, 1, 1, 10, nil) // steps
        worksheet_set_column(worksheet, 2, 2, 12, nil) // sleep
        worksheet_set_column(worksheet, 3, 3, 12, nil) // hrv
        worksheet_set_column(worksheet, 4, 4, 14, nil) // rhr
        worksheet_set_column(worksheet, 5, 5, 16, nil) // energy
        worksheet_set_column(worksheet, 6, 6, 10, nil) // validDay
        worksheet_set_column(worksheet, 7, 7, 26, nil) // syncedAt

        // 关闭并写入文件
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
