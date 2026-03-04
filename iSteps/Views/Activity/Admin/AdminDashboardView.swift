import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Charts
import UniformTypeIdentifiers

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

enum AdminRangeDays: Int, CaseIterable {
    case d7 = 7
    case d14 = 14
    case d30 = 30
    case d90 = 90

    var title: String {
        switch self {
        case .d7: return "Last 7 days"
        case .d14: return "Last 14 days"
        case .d30: return "Last 30 days"
        case .d90: return "Last 90 days"
        }
    }
}

// MARK: - View

struct AdminDashboardView: View {

    @EnvironmentObject private var session: EmailAuthenticationController

    // same look & feel as pilot
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

    @State private var range: AdminRangeDays = .d14
    @State private var dailyRows: [DailyRow] = []
    @State private var isLoading: Bool = false
    @State private var errorText: String? = nil

    // export
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
            .onAppear {
                reloadAll()
            }
            .sheet(isPresented: $showShare) {
                if let exportURL {
                    ShareSheet(activityItems: [exportURL])
                }
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
        if let uid = selectedUID,
           let p = participants.first(where: { $0.id == uid }) {
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
                    Picker("", selection: $range) {
                        ForEach(AdminRangeDays.allCases, id: \.self) { r in
                            Text(r.title).tag(r)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: range) { _ in
                        reloadDaily()
                    }
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

                    if let uid = selectedUID,
                       let p = participants.first(where: { $0.id == uid }) {
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

    private var trendsCard: some View {
        glassCard(title: "Trends", trailingIcon: "chart.xyaxis.line") {
            VStack(alignment: .leading, spacing: 16) {
                if dailyRows.isEmpty {
                    Text("No daily data yet for selected participant.")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundColor(.white.opacity(0.65))
                } else {
                    metricChart(
                        title: "Steps",
                        systemImage: "figure.walk",
                        points: dailyRows.compactMap { row in
                            guard let v = row.steps else { return nil }
                            return ChartPoint(dateId: row.dateId, value: Double(v))
                        },
                        valueFormat: { "\(Int($0))" }
                    )

                    metricChart(
                        title: "Sleep Hours",
                        systemImage: "bed.double",
                        points: dailyRows.compactMap { row in
                            guard let v = row.sleepHours else { return nil }
                            return ChartPoint(dateId: row.dateId, value: v)
                        },
                        valueFormat: { String(format: "%.2f", $0) }
                    )

                    metricChart(
                        title: "HRV SDNN (ms)",
                        systemImage: "waveform.path.ecg",
                        points: dailyRows.compactMap { row in
                            guard let v = row.hrvSDNNms else { return nil }
                            return ChartPoint(dateId: row.dateId, value: v)
                        },
                        valueFormat: { String(format: "%.2f", $0) }
                    )

                    metricChart(
                        title: "Resting HR (bpm)",
                        systemImage: "heart",
                        points: dailyRows.compactMap { row in
                            guard let v = row.restingHRbpm else { return nil }
                            return ChartPoint(dateId: row.dateId, value: v)
                        },
                        valueFormat: { String(format: "%.0f", $0) }
                    )

                    metricChart(
                        title: "Active Energy (kcal)",
                        systemImage: "flame",
                        points: dailyRows.compactMap { row in
                            guard let v = row.activeEnergyKcal else { return nil }
                            return ChartPoint(dateId: row.dateId, value: v)
                        },
                        valueFormat: { String(format: "%.1f", $0) }
                    )
                }
            }
        }
    }

    private var exportCard: some View {
        glassCard(title: "Export", trailingIcon: "square.and.arrow.up") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Export selected participant’s daily rows as CSV (Excel-compatible).")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))

                Button {
                    exportCSV()
                } label: {
                    HStack {
                        Image(systemName: "doc.badge.plus")
                        Text("Download CSV")
                    }
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                }
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

    // MARK: - Chart helper

    struct ChartPoint: Identifiable {
        let id = UUID()
        let dateId: String
        let value: Double

        var date: Date {
            AdminDashboardView.parseDateId(dateId) ?? Date()
        }
    }

    private func metricChart(title: String, systemImage: String, points: [ChartPoint], valueFormat: @escaping (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundColor(.white.opacity(0.85))
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundColor(.white)
                Spacer()

                if let last = points.sorted(by: { $0.dateId > $1.dateId }).first {
                    Text(valueFormat(last.value))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.08))
                        .clipShape(Capsule())
                }
            }

            Chart(points.sorted(by: { $0.date < $1.date })) { p in
                LineMark(
                    x: .value("Date", p.date),
                    y: .value("Value", p.value)
                )
                PointMark(
                    x: .value("Date", p.date),
                    y: .value("Value", p.value)
                )
            }
            .frame(height: 160)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4))
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4))
            }
            .padding(10)
            .background(.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
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
            .limit(to: range.rawValue)
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

    // MARK: - Export CSV (Excel-friendly)

    private func exportCSV() {
        guard let uid = selectedUID else { return }
        let display = participants.first(where: { $0.id == uid })?.display ?? uid

        // Sort ascending by date
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

        let fileName = "pilot_export_\(safeName)_\(range.rawValue)d.csv"
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
