import SwiftUI
import CryptoKit
import SafariServices
import FirebaseAuth
import FirebaseFirestore

// MARK: - App Mode

enum AppMode: String {
    case pilot
    case full
}

// MARK: - Root Switcher

struct RootSwitcherView: View {
    @AppStorage("app_mode") private var appModeRaw: String = AppMode.pilot.rawValue

    var body: some View {
        let mode = AppMode(rawValue: appModeRaw) ?? .pilot
        Group {
            switch mode {
            case .pilot:
                PilotLandingView(
                    onUnlock: { appModeRaw = AppMode.full.rawValue }
                )
            case .full:
                FullTabView(
                    onLockBack: { appModeRaw = AppMode.pilot.rawValue }
                )
            }
        }
    }
}

// MARK: - Full App Tabs

struct FullTabView: View {
    let onLockBack: () -> Void

    var body: some View {
        TabView {
            BurnoutScoreView(steps: [])
                .tabItem { Label("Home", systemImage: "gauge") }

            ActivityView(steps: [])
                .tabItem { Label("Activity", systemImage: "figure.walk") }

            TrendsView(steps: [])
                .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                onLockBack()
            } label: {
                Image(systemName: "lock.open")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(10)
                    .background(.black.opacity(0.35))
                    .clipShape(Capsule())
                    .padding(.trailing, 14)
                    .padding(.top, 10)
            }
        }
    }
}

// MARK: - Upload State (pilot UI)

enum PilotUploadState: String {
    case ok
    case pending
    case failed

    var title: String {
        switch self {
        case .ok: return "Data uploaded successfully"
        case .pending: return "Upload pending"
        case .failed: return "Upload failed"
        }
    }

    var detail: String {
        switch self {
        case .ok: return "Your daily summaries are synced to the research server."
        case .pending: return "We’ll upload automatically when internet is available."
        case .failed: return "Please open the app on Wi-Fi or try again later."
        }
    }

    var icon: String {
        switch self {
        case .ok: return "checkmark.icloud"
        case .pending: return "icloud"
        case .failed: return "exclamationmark.icloud"
        }
    }

    var badgeText: String {
        switch self {
        case .ok: return "OK"
        case .pending: return "PENDING"
        case .failed: return "FAILED"
        }
    }

    var badgeColor: Color {
        switch self {
        case .ok: return .green.opacity(0.9)
        case .pending: return .orange.opacity(0.95)
        case .failed: return .red.opacity(0.9)
        }
    }
}

// MARK: - Today Signals model

enum PilotTodaySignals {
    case loading
    case result(SignalsResult)

    struct SignalsResult {
        let stepsOK: Bool
        let sleepOK: Bool
        let hrvOK: Bool
        let rhrOK: Bool
        let energyOK: Bool

        var collectedCount: Int {
            [stepsOK, sleepOK, hrvOK, rhrOK, energyOK].filter { $0 }.count
        }
    }
}

// MARK: - Admin Unlock Sheet

struct AdminUnlockSheet: View {
    @Binding var password: String
    let onCancel: () -> Void
    let onUnlock: () -> Void

    var body: some View {
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

                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(10)
                                .background(.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Admin Access")
                                    .font(.system(.headline, design: .rounded).weight(.semibold))
                                    .foregroundColor(.white)
                                Text("Enter password to open full app")
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundColor(.white.opacity(0.65))
                            }

                            Spacer()
                        }

                        Divider().overlay(.white.opacity(0.12))

                        SecureField("Password", text: $password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(.white.opacity(0.10), lineWidth: 1)
                            )
                            .foregroundColor(.white)
                    }
                    .padding(16)
                    .background(.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(.white.opacity(0.10), lineWidth: 1)
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    HStack(spacing: 12) {
                        Button { onCancel() } label: {
                            Text("Cancel")
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .foregroundColor(.white.opacity(0.9))

                        Button { onUnlock() } label: {
                            Text("Unlock")
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(.white.opacity(0.14))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)

                    Spacer()
                }
            }
            .navigationBarHidden(true)
        }
    }
}

// MARK: - Admin Password Verification

//private let ADMIN_PASSWORD_SHA256 = "be5557476d108b8a6b3aa860eed9b8598c6acea6b2307eeaccc24cb78b2c9c56"
//
//func verifyAdminPassword(_ input: String) -> Bool {
//    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
//    guard !trimmed.isEmpty else { return false }
//    return sha256Hex(trimmed).lowercased() == ADMIN_PASSWORD_SHA256.lowercased()
//}

private func sha256Hex(_ s: String) -> String {
    let data = Data(s.utf8)
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
}

// MARK: - PilotSafariView

struct PilotSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) { }
}

// MARK: - PilotLandingView Helpers (Non-HealthKit)

extension PilotLandingView {

    // MARK: - Participant profile upsert (email -> participants/{uid})
    // This enables admin dashboard to list users by email.
    
    func backfillLastDaysIfNeeded(days: Int = 14) {

        // ✅ No flag: always attempt backfill (safe because daily docs are overwritten by dateId)
        guard let uid = Auth.auth().currentUser?.uid else {
            print("Backfill blocked: not logged in")
            return
        }

        refreshHealthAuthorizationReliable {

            guard self.healthAuthorized else {
                print("Backfill failed: HealthKit not authorized")
                return
            }

            let cal = Calendar.current
            let todayStart = cal.startOfDay(for: Date())
            let group = DispatchGroup()

            for offset in 0..<days {
                guard let day = cal.date(byAdding: .day, value: -offset, to: todayStart) else { continue }
                let dateId = Self.dateId(for: day)

                group.enter()

                self.fetchDailySummaryForUpload(for: day) { payload in
                    defer { group.leave() }

                    guard let payload else {
                        print("Backfill skipped \(dateId): payload nil")
                        return
                    }

                    // Only backfill days that likely contain Apple Watch physiological data
                    guard let watchLikelyDay = payload["watchLikelyDay"] as? Bool,
                          watchLikelyDay else {
                        print("Backfill skipped \(dateId): likely iPhone-only day")
                        return
                    }

                    self.writeDailyPayloadToFirestore(uid: uid, dateId: dateId, payload: payload)
                }
            }

            group.notify(queue: .main) {
                print("Backfill completed (no flag)")
            }
        }
    }

    func upsertParticipantProfile() {
        guard let user = Auth.auth().currentUser else { return }
        let uid = user.uid
        let email = user.email ?? ""

        Firestore.firestore()
            .collection("participants")
            .document(uid)
            .setData([
                "uid": uid,
                "email": email,
                "display": email.isEmpty ? uid : email,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true) { error in
                if let error {
                    print("⚠️ upsertParticipantProfile failed: \(error)")
                } else {
                    print("✅ upsertParticipantProfile ok: participants/\(uid)")
                }
            }
    }

    // MARK: - Upload Now integration (NO new button; called by existing button)

    func uploadNowTapped() {
        // 1) Must be logged in
        guard let uid = Auth.auth().currentUser?.uid else {
            uploadStateRaw = PilotUploadState.failed.rawValue
            print("❌ Upload blocked: not logged in")
            return
        }

        // ✅ Ensure participant root doc has email for admin listing
        upsertParticipantProfile()

        // 2) Mark pending immediately for UI
        uploadStateRaw = PilotUploadState.pending.rawValue

        // 3) Ensure HealthKit access then fetch values then upload
        refreshHealthAuthorizationReliable {
            guard self.healthAuthorized else {
                self.uploadStateRaw = PilotUploadState.failed.rawValue
                print("❌ Upload failed: HealthKit not authorized")
                return
            }

            self.fetchDailySummaryForUpload(for: Date()) { payload in
                guard let payload else {
                    self.uploadStateRaw = PilotUploadState.failed.rawValue
                    print("❌ Upload failed: could not build daily payload")
                    return
                }

                self.writeDailyPayloadToFirestore(uid: uid, dateId: payload["date"] as? String ?? Self.todayDateId(), payload: payload)
            }
        }
    }

    // Build payload for Firestore from HealthKit numeric queries.
    private func fetchDailySummaryForUpload(for date: Date, completion: @escaping ([String: Any]?) -> Void) {

        let dateId = Self.dateId(for: date)

        let group = DispatchGroup()

        var steps: Double? = nil
        var energy: Double? = nil
        var hrvMs: Double? = nil
        var rhr: Double? = nil
        var sleepHours: Double? = nil

        group.enter()
        fetchCumulativeNumber(for: date, .stepCount) { v in
            steps = v
            group.leave()
        }

        group.enter()
        fetchCumulativeNumber(for: date, .activeEnergyBurned) { v in
            energy = v
            group.leave()
        }

        group.enter()
        fetchDailyAverage(for: date, .heartRateVariabilitySDNN) { v in
            hrvMs = v
            group.leave()
        }

        group.enter()
        fetchDailyAverage(for: date, .restingHeartRate) { v in
            rhr = v
            group.leave()
        }

        group.enter()
        fetchSleepHours(for: date) { v in
            sleepHours = v
            group.leave()
        }

        group.notify(queue: .main) {
            let hasSteps = (steps ?? 0) > 0
            let hasEnergy = (energy ?? 0) > 0
            let hasHRV = (hrvMs != nil)
            let hasRHR = (rhr != nil)
            let hasSleep = (sleepHours ?? 0) > 0
            let watchLikelyDay = hasSleep || hasHRV || hasRHR
            let phoneOnlyLikelyDay = (hasSteps || hasEnergy) && !watchLikelyDay

            let validDay = hasSleep && (hasHRV || hasRHR) && (hasSteps || hasEnergy)

            var payload: [String: Any] = [
                "date": dateId,
                "hasSteps": hasSteps,
                "hasEnergy": hasEnergy,
                "hasHRV": hasHRV,
                "hasRHR": hasRHR,
                "hasSleep": hasSleep,
                "validDay": validDay,
                "syncedAt": FieldValue.serverTimestamp(),
                "syncedAtEpoch": Date().timeIntervalSince1970,
                "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                // Indicates this day likely contains Apple Watch physiological data
                "watchLikelyDay": watchLikelyDay,

                // Indicates data likely came only from iPhone (no HRV/RHR/Sleep)
                "phoneOnlyLikelyDay": phoneOnlyLikelyDay
                
            ]

            if let steps { payload["steps"] = Int(steps.rounded()) }
            if let energy { payload["activeEnergyKcal"] = energy }
            if let hrvMs { payload["hrvSDNN_ms"] = hrvMs }
            if let rhr { payload["restingHR_bpm"] = rhr }
            if let sleepHours { payload["sleepHours"] = sleepHours }

            completion(payload)
        }
    }

    private func writeDailyPayloadToFirestore(uid: String, dateId: String, payload: [String: Any]) {
        let db = Firestore.firestore()

        let docRef = db.collection("participants")
            .document(uid)
            .collection("daily")
            .document(dateId)

        docRef.setData(payload, merge: true) { error in
            if let error {
                self.uploadStateRaw = PilotUploadState.failed.rawValue
                print("❌ Firestore upload failed: \(error)")
            } else {
                self.lastUploadEpoch = Date().timeIntervalSince1970
                self.uploadStateRaw = PilotUploadState.ok.rawValue
                print("✅ Firestore upload success: participants/\(uid)/daily/\(dateId)")
            }
        }
    }

    // MARK: - Reusable UI

    func glassCard<Content: View>(
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

    func statusRow(title: String, value: String, valueColor: Color, icon: String) -> some View {
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

    func dataCheckRow(name: String, ok: Bool) -> some View {
        HStack {
            Text(name)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundColor(.white)
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(ok ? .green.opacity(0.95) : .orange.opacity(0.95))
                Text(ok ? "OK" : "Missing")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundColor(.white.opacity(0.8))
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

    func miniPill(_ text: String, icon: String) -> some View {
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

    // MARK: - Study bookkeeping

    func bootstrapStudyIfNeeded() {
        if studyStartDateEpoch <= 0 {
            studyStartDateEpoch = Date().timeIntervalSince1970
        }
        if participantId.isEmpty {
            participantId = "PILOT"
        }
    }

    func studyDayIndex() -> Int {
        guard studyStartDateEpoch > 0 else { return 1 }
        let start = Date(timeIntervalSince1970: studyStartDateEpoch)
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: start),
            to: Calendar.current.startOfDay(for: Date())
        ).day ?? 0
        return max(1, days + 1)
    }

    // MARK: - Formatting

    func formatDateTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }

    // MARK: - DateId utility (doc id for Firestore)
    static func dateId(for date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func todayDateId() -> String {
        return dateId(for: Date())
    }
}
