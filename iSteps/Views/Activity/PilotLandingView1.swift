////
////  PilotMode.swift
////  Last Call Before Burnout (or iSteps)
////
////  Drop this file into your project.
////  It adds:
////   - Pilot landing page (research dashboard style)
////   - Admin unlock (password) -> switches to full app tabs
////   - Root switcher (Pilot <-> Full)
////
////  IMPORTANT:
////  1) If you already have `Step` defined elsewhere, DELETE the Step struct below to avoid redeclare.
////  2) Replace the placeholders in `FullTabView()` with your actual tab container (if you already have one).
////  3) Set ADMIN_PASSWORD_SHA256 to your own hash (see helper at bottom).
////
//
//import SwiftUI
//import HealthKit
//import CryptoKit
//import SafariServices
//
//// MARK: - App Mode
//
//enum AppMode: String {
//    case pilot
//    case full
//}
//
//// MARK: - Root Switcher
//
//struct RootSwitcherView: View {
//    @AppStorage("app_mode") private var appModeRaw: String = AppMode.pilot.rawValue
//
//    var body: some View {
//        let mode = AppMode(rawValue: appModeRaw) ?? .pilot
//        Group {
//            switch mode {
//            case .pilot:
//                PilotLandingView(
//                    onUnlock: { appModeRaw = AppMode.full.rawValue }
//                )
//            case .full:
//                FullTabView(
//                    onLockBack: { appModeRaw = AppMode.pilot.rawValue }
//                )
//            }
//        }
//    }
//}
//
//// MARK: - Pilot Landing (Research Dashboard)
//
//struct PilotLandingView: View {
//
//    // Admin unlock callback (switch to Full app)
//    let onUnlock: () -> Void
//
//    // Study settings
//    private let studyTotalDays: Int = 14
//
//    // Persisted participant + study start
//    @AppStorage("participant_id") private var participantId: String = ""
//    @AppStorage("study_start_date") private var studyStartDateEpoch: Double = 0 // timeIntervalSince1970
//
//    // Persisted last sync / upload info (you can update these when you actually fetch & upload)
//    @AppStorage("last_sync_epoch") private var lastSyncEpoch: Double = 0
//    @AppStorage("last_upload_epoch") private var lastUploadEpoch: Double = 0
//    @AppStorage("upload_state") private var uploadStateRaw: String = UploadState.ok.rawValue
//
//    // Admin UI
//    @State private var showAdminSheet = false
//    @State private var adminPassword = ""
//    @State private var showWrongPasswordAlert = false
//
//    // Survey UI
//    @State private var isSurveyPresented = false
//
//    // Health status
//    private let hk = HKHealthStore()
//    @State private var healthAuthorized: Bool = false
//    @State private var watchLikelyConnected: Bool = false // best-effort proxy
//    @State private var todaySignals: TodaySignals = .loading
//
//    // Survey placeholder (you can wire to your survey schedule later)
//    @State private var nextSurveyText: String = "Not scheduled"
//    @State private var surveyOverdue: Bool = false
//
//    var body: some View {
//        NavigationView {
//            ZStack {
//                pilotBackground.ignoresSafeArea()
//
//                ScrollView(showsIndicators: false) {
//                    VStack(spacing: 14) {
//
//                        headerCard
//
//                        studyStatusCard
//
//                        deviceStatusCard
//
//                        todaysDataCard
//
//                        surveyCard
//
//                        uploadStatusCard
//
//                        Spacer(minLength: 20)
//                    }
//                    .padding(.horizontal, 16)
//                    .padding(.top, 12)
//                    .padding(.bottom, 90)
//                }
//            }
//            .navigationTitle("Pilot")
//            .navigationBarTitleDisplayMode(.inline)
//            .toolbar {
//                ToolbarItemGroup(placement: .navigationBarTrailing) {
//
//                    // Survey button (same behavior as Home)
//                    Button {
//                        isSurveyPresented = true
//                    } label: {
//                        Image(systemName: "doc.text")
//                    }
//                    .accessibilityLabel("Survey")
//                    .sheet(isPresented: $isSurveyPresented) {
//                        SafariView(url: URL(string: "https://form.typeform.com/to/STFEkNs0")!)
//                    }
//
//                    // Admin button
//                    Button {
//                        showAdminSheet = true
//                    } label: {
//                        Image(systemName: "lock.circle")
//                    }
//                    .accessibilityLabel("Admin")
//                }
//            }
//            .sheet(isPresented: $showAdminSheet) {
//                AdminUnlockSheet(
//                    password: $adminPassword,
//                    onCancel: {
//                        adminPassword = ""
//                        showAdminSheet = false
//                    },
//                    onUnlock: {
//                        let ok = verifyAdminPassword(adminPassword)
//                        if ok {
//                            adminPassword = ""
//                            showAdminSheet = false
//                            onUnlock()
//                        } else {
//                            showWrongPasswordAlert = true
//                        }
//                    }
//                )
//                .presentationDetents([.medium])
//            }
//            .alert("Incorrect password", isPresented: $showWrongPasswordAlert) {
//                Button("OK", role: .cancel) { }
//            } message: {
//                Text("Admin access denied.")
//            }
//            .onAppear {
//                bootstrapStudyIfNeeded()
//                refreshAllStatuses()
//            }
//        }
//    }
//
//    // MARK: - Background
//
//    private var pilotBackground: some View {
//        LinearGradient(
//            colors: [
//                Color.black,
//                Color(red: 0.07, green: 0.08, blue: 0.12),
//                Color(red: 0.10, green: 0.07, blue: 0.16)
//            ],
//            startPoint: .topLeading,
//            endPoint: .bottomTrailing
//        )
//    }
//
//    // MARK: - Header
//
//    private var headerCard: some View {
//        VStack(alignment: .leading, spacing: 10) {
//            HStack(spacing: 10) {
//                Image(systemName: "sparkles")
//                    .font(.system(size: 16, weight: .semibold))
//                    .foregroundStyle(.white.opacity(0.9))
//                    .padding(10)
//                    .background(.white.opacity(0.08))
//                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
//
//                VStack(alignment: .leading, spacing: 2) {
//                    Text("Burnout Pilot Study")
//                        .font(.system(.headline, design: .rounded).weight(.semibold))
//                        .foregroundColor(.white)
//                    Text("Data collection dashboard")
//                        .font(.system(.subheadline, design: .rounded))
//                        .foregroundColor(.white.opacity(0.65))
//                }
//
//                Spacer()
//
//                Text("RESEARCH")
//                    .font(.system(.caption, design: .rounded).weight(.bold))
//                    .foregroundColor(.white.opacity(0.85))
//                    .padding(.horizontal, 10)
//                    .padding(.vertical, 6)
//                    .background(.white.opacity(0.08))
//                    .clipShape(Capsule())
//            }
//
//            Divider().overlay(.white.opacity(0.12))
//
//            HStack {
//                Text("Participant")
//                    .font(.system(.caption, design: .rounded).weight(.semibold))
//                    .foregroundColor(.white.opacity(0.6))
//                Spacer()
//                Text(participantId.isEmpty ? "Not set" : participantId)
//                    .font(.system(.subheadline, design: .rounded).weight(.bold))
//                    .foregroundColor(.white)
//            }
//        }
//        .padding(16)
//        .background(.white.opacity(0.06))
//        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
//        .overlay(
//            RoundedRectangle(cornerRadius: 18, style: .continuous)
//                .stroke(.white.opacity(0.10), lineWidth: 1)
//        )
//    }
//
//    // MARK: - Study status
//
//    private var studyStatusCard: some View {
//        let day = studyDayIndex()
//        let remaining = max(0, studyTotalDays - day)
//
//        return glassCard(title: "Study Status", trailingIcon: "calendar") {
//            VStack(alignment: .leading, spacing: 10) {
//                HStack {
//                    miniPill("Day \(day) / \(studyTotalDays)", icon: "flag.checkered")
//                    Spacer()
//                    Text("\(remaining) days remaining")
//                        .font(.system(.footnote, design: .rounded))
//                        .foregroundColor(.white.opacity(0.65))
//                }
//
//                Divider().overlay(.white.opacity(0.12))
//
//                VStack(alignment: .leading, spacing: 6) {
//                    Text("Goal")
//                        .font(.system(.caption, design: .rounded).weight(.semibold))
//                        .foregroundColor(.white.opacity(0.6))
//                    Text("Wear Apple Watch daily, especially overnight.")
//                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
//                        .foregroundColor(.white)
//                    Text("This app does not provide medical diagnosis.")
//                        .font(.system(.footnote, design: .rounded))
//                        .foregroundColor(.white.opacity(0.6))
//                }
//            }
//        }
//    }
//
//    // MARK: - Device status
//
//    private var deviceStatusCard: some View {
//        glassCard(title: "Device Status", trailingIcon: "applewatch") {
//            VStack(spacing: 10) {
//
//                statusRow(
//                    title: "Health Access",
//                    value: healthAuthorized ? "Granted" : "Not Granted",
//                    valueColor: healthAuthorized ? .green.opacity(0.9) : .red.opacity(0.9),
//                    icon: "heart.fill"
//                )
//
//                statusRow(
//                    title: "Watch",
//                    value: watchLikelyConnected ? "Connected" : "Unknown",
//                    valueColor: watchLikelyConnected ? .green.opacity(0.9) : .white.opacity(0.6),
//                    icon: "applewatch"
//                )
//
//                statusRow(
//                    title: "Last Sync",
//                    value: lastSyncEpoch > 0 ? formatDateTime(Date(timeIntervalSince1970: lastSyncEpoch)) : "—",
//                    valueColor: .white.opacity(0.85),
//                    icon: "arrow.triangle.2.circlepath"
//                )
//
//                Button {
//                    refreshAllStatuses()
//                } label: {
//                    HStack {
//                        Image(systemName: "arrow.triangle.2.circlepath")
//                        Text("Sync Now")
//                    }
//                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
//                    .padding(.horizontal, 14)
//                    .padding(.vertical, 8)
//                    .background(Color.white.opacity(0.08))
//                    .clipShape(Capsule())
//                }
//                .foregroundColor(.white)
//
//                Text("Tip: If Sleep/HRV is missing, wear your Apple Watch overnight and keep it charged.")
//                    .font(.system(.footnote, design: .rounded))
//                    .foregroundColor(.white.opacity(0.6))
//            }
//        }
//    }
//
//    // MARK: - Today's data
//
//    private var todaysDataCard: some View {
//        glassCard(title: "Today’s Data", trailingIcon: "waveform.path.ecg") {
//            switch todaySignals {
//            case .loading:
//                HStack(spacing: 10) {
//                    ProgressView()
//                    Text("Checking signals…")
//                        .font(.system(.subheadline, design: .rounded))
//                        .foregroundColor(.white.opacity(0.8))
//                }
//
//            case .result(let r):
//                VStack(alignment: .leading, spacing: 10) {
//                    dataCheckRow(name: "Steps", ok: r.stepsOK)
//                    dataCheckRow(name: "Sleep", ok: r.sleepOK)
//                    dataCheckRow(name: "HRV", ok: r.hrvOK)
//                    dataCheckRow(name: "Resting HR", ok: r.rhrOK)
//                    dataCheckRow(name: "Active Energy", ok: r.energyOK)
//
//                    Divider().overlay(.white.opacity(0.12))
//
//                    let collected = r.collectedCount
//                    Text("Data completeness: \(collected) / 5 signals")
//                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
//                        .foregroundColor(.white)
//
//                    if collected < 4 {
//                        Text("Some signals are missing. This is common—please keep wearing your Apple Watch, especially overnight.")
//                            .font(.system(.footnote, design: .rounded))
//                            .foregroundColor(.white.opacity(0.65))
//                    } else {
//                        Text("Great—signals look good today.")
//                            .font(.system(.footnote, design: .rounded))
//                            .foregroundColor(.white.opacity(0.65))
//                    }
//                }
//            }
//        }
//    }
//
//    // MARK: - Survey
//
//    private var surveyCard: some View {
//        glassCard(title: "Survey", trailingIcon: "doc.text") {
//            VStack(alignment: .leading, spacing: 10) {
//                HStack {
//                    Text("Next survey")
//                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
//                        .foregroundColor(.white)
//                    Spacer()
//                    Text(nextSurveyText)
//                        .font(.system(.subheadline, design: .rounded).weight(.bold))
//                        .foregroundColor(surveyOverdue ? .orange.opacity(0.95) : .white.opacity(0.85))
//                }
//
//                Text("You will be prompted when your study survey is available.")
//                    .font(.system(.footnote, design: .rounded))
//                    .foregroundColor(.white.opacity(0.6))
//
//                Button {
//                    isSurveyPresented = true
//                } label: {
//                    HStack {
//                        Image(systemName: "square.and.pencil")
//                        Text("Complete Survey")
//                    }
//                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
//                    .padding(.horizontal, 14)
//                    .padding(.vertical, 8)
//                    .background(Color.white.opacity(0.08))
//                    .clipShape(Capsule())
//                }
//                .foregroundColor(.white)
//            }
//        }
//    }
//
//    // MARK: - Upload
//
//    private var uploadStatusCard: some View {
//        let st = UploadState(rawValue: uploadStateRaw) ?? .ok
//
//        return glassCard(title: "Upload Status", trailingIcon: "icloud.and.arrow.up") {
//            VStack(alignment: .leading, spacing: 10) {
//                HStack {
//                    Text(st.title)
//                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
//                        .foregroundColor(.white)
//                    Spacer()
//                    Text(st.badgeText)
//                        .font(.system(.caption, design: .rounded).weight(.bold))
//                        .foregroundColor(st.badgeColor)
//                        .padding(.horizontal, 10)
//                        .padding(.vertical, 6)
//                        .background(.white.opacity(0.08))
//                        .clipShape(Capsule())
//                }
//
//                HStack {
//                    Image(systemName: st.icon)
//                        .foregroundColor(st.badgeColor.opacity(0.95))
//                    Text(st.detail)
//                        .font(.system(.footnote, design: .rounded))
//                        .foregroundColor(.white.opacity(0.65))
//                }
//
//                statusRow(
//                    title: "Last Upload",
//                    value: lastUploadEpoch > 0 ? formatDateTime(Date(timeIntervalSince1970: lastUploadEpoch)) : "—",
//                    valueColor: .white.opacity(0.85),
//                    icon: "clock"
//                )
//
//                Button {
//                    lastUploadEpoch = Date().timeIntervalSince1970
//                    uploadStateRaw = UploadState.ok.rawValue
//                } label: {
//                    HStack {
//                        Image(systemName: "icloud.and.arrow.up")
//                        Text("Upload Now")
//                    }
//                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
//                    .padding(.horizontal, 14)
//                    .padding(.vertical, 8)
//                    .background(Color.white.opacity(0.08))
//                    .clipShape(Capsule())
//                }
//                .foregroundColor(.white)
//            }
//        }
//    }
//
//    // MARK: - Reusable UI
//
//    private func glassCard<Content: View>(title: String, trailingIcon: String, @ViewBuilder content: () -> Content) -> some View {
//        VStack(alignment: .leading, spacing: 12) {
//            HStack {
//                Text(title)
//                    .font(.system(.headline, design: .rounded).weight(.semibold))
//                    .foregroundColor(.white)
//                Spacer()
//                Image(systemName: trailingIcon)
//                    .foregroundColor(.white.opacity(0.7))
//            }
//            Divider().overlay(.white.opacity(0.12))
//            content()
//        }
//        .padding(16)
//        .background(.white.opacity(0.06))
//        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
//        .overlay(
//            RoundedRectangle(cornerRadius: 18, style: .continuous)
//                .stroke(.white.opacity(0.10), lineWidth: 1)
//        )
//    }
//
//    private func statusRow(title: String, value: String, valueColor: Color, icon: String) -> some View {
//        HStack(spacing: 12) {
//            Image(systemName: icon)
//                .font(.system(size: 16, weight: .semibold))
//                .foregroundColor(.white.opacity(0.85))
//                .frame(width: 28, height: 28)
//                .background(.white.opacity(0.08))
//                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
//
//            Text(title)
//                .font(.system(.subheadline, design: .rounded).weight(.semibold))
//                .foregroundColor(.white)
//
//            Spacer()
//
//            Text(value)
//                .font(.system(.subheadline, design: .rounded).weight(.bold))
//                .foregroundColor(valueColor)
//        }
//        .padding(12)
//        .background(.white.opacity(0.05))
//        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
//        .overlay(
//            RoundedRectangle(cornerRadius: 14, style: .continuous)
//                .stroke(.white.opacity(0.08), lineWidth: 1)
//        )
//    }
//
//    private func dataCheckRow(name: String, ok: Bool) -> some View {
//        HStack {
//            Text(name)
//                .font(.system(.subheadline, design: .rounded).weight(.semibold))
//                .foregroundColor(.white)
//            Spacer()
//            HStack(spacing: 6) {
//                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
//                    .foregroundColor(ok ? .green.opacity(0.95) : .orange.opacity(0.95))
//                Text(ok ? "OK" : "Missing")
//                    .font(.system(.caption, design: .rounded).weight(.bold))
//                    .foregroundColor(.white.opacity(0.8))
//            }
//        }
//        .padding(12)
//        .background(.white.opacity(0.05))
//        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
//        .overlay(
//            RoundedRectangle(cornerRadius: 14, style: .continuous)
//                .stroke(.white.opacity(0.08), lineWidth: 1)
//        )
//    }
//
//    private func miniPill(_ text: String, icon: String) -> some View {
//        HStack(spacing: 6) {
//            Image(systemName: icon)
//            Text(text)
//        }
//        .font(.system(.caption, design: .rounded).weight(.semibold))
//        .foregroundColor(.white.opacity(0.85))
//        .padding(.horizontal, 10)
//        .padding(.vertical, 7)
//        .background(.white.opacity(0.08))
//        .clipShape(Capsule())
//    }
//
//    // MARK: - Study bookkeeping
//
//    private func bootstrapStudyIfNeeded() {
//        if studyStartDateEpoch <= 0 {
//            studyStartDateEpoch = Date().timeIntervalSince1970
//        }
//        if participantId.isEmpty {
//            participantId = "PILOT"
//        }
//    }
//
//    private func studyDayIndex() -> Int {
//        guard studyStartDateEpoch > 0 else { return 1 }
//        let start = Date(timeIntervalSince1970: studyStartDateEpoch)
//        let days = Calendar.current.dateComponents(
//            [.day],
//            from: Calendar.current.startOfDay(for: start),
//            to: Calendar.current.startOfDay(for: Date())
//        ).day ?? 0
//        return max(1, days + 1)
//    }
//
//    // MARK: - Health checks (best-effort)
//
//    private func requiredReadTypes() -> Set<HKObjectType> {
//        return [
//            HKObjectType.quantityType(forIdentifier: .stepCount)!,
//            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
//            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
//            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
//            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
//        ]
//    }
//
//    private func refreshAllStatuses() {
//        // Update last sync "now" for pilot UX.
//        lastSyncEpoch = Date().timeIntervalSince1970
//
//        // Check/request access, then refresh signals.
//        refreshHealthAuthorizationReliable {
//            self.watchLikelyConnected = self.healthAuthorized
//            self.refreshTodaySignals()
//
//            // Survey placeholder (you can change to your schedule later).
//            self.nextSurveyText = "Not scheduled"
//            self.surveyOverdue = false
//        }
//    }
//
//    private func refreshHealthAuthorizationReliable(completion: @escaping () -> Void) {
//        guard HKHealthStore.isHealthDataAvailable() else {
//            healthAuthorized = false
//            completion()
//            return
//        }
//
//        let types = requiredReadTypes()
//
//        hk.getRequestStatusForAuthorization(toShare: [], read: types) { status, _ in
//            DispatchQueue.main.async {
//                switch status {
//                case .unnecessary:
//                    // Authorization was requested before (granted or denied). Verify by query.
//                    self.verifyReadAccessByQuery(completion: completion)
//
//                case .shouldRequest:
//                    // Request authorization for the required read types.
//                    self.hk.requestAuthorization(toShare: [], read: types) { _, _ in
//                        DispatchQueue.main.async {
//                            self.verifyReadAccessByQuery(completion: completion)
//                        }
//                    }
//
//                @unknown default:
//                    self.healthAuthorized = false
//                    completion()
//                }
//            }
//        }
//    }
//
//    private func verifyReadAccessByQuery(completion: @escaping () -> Void) {
//        // A lightweight stepCount query that returns:
//        // - data (authorized and there is at least one sample), or
//        // - empty but no error (authorized but no data), or
//        // - error (commonly not authorized / restricted).
//        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
//            healthAuthorized = false
//            completion()
//            return
//        }
//
//        let end = Date()
//        let start = Calendar.current.date(byAdding: .day, value: -1, to: end)!
//        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
//
//        let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: nil) { _, _, error in
//            DispatchQueue.main.async {
//                self.healthAuthorized = (error == nil)
//                completion()
//            }
//        }
//        hk.execute(q)
//    }
//
//    private func refreshTodaySignals() {
//        todaySignals = .loading
//
//        guard healthAuthorized else {
//            todaySignals = .result(.init(stepsOK: false, sleepOK: false, hrvOK: false, rhrOK: false, energyOK: false))
//            return
//        }
//
//        let group = DispatchGroup()
//        var stepsOK = false
//        var sleepOK = false
//        var hrvOK = false
//        var rhrOK = false
//        var energyOK = false
//
//        group.enter()
//        hasTodayCumulative(.stepCount) { ok in
//            stepsOK = ok
//            group.leave()
//        }
//
//        group.enter()
//        hasAnyCategoryLast24h(.sleepAnalysis) { ok in
//            sleepOK = ok
//            group.leave()
//        }
//
//        group.enter()
//        hasAnyQuantityLast24h(.heartRateVariabilitySDNN) { ok in
//            hrvOK = ok
//            group.leave()
//        }
//
//        group.enter()
//        hasAnyQuantityLast24h(.restingHeartRate) { ok in
//            rhrOK = ok
//            group.leave()
//        }
//
//        group.enter()
//        hasTodayCumulative(.activeEnergyBurned) { ok in
//            energyOK = ok
//            group.leave()
//        }
//
//        group.notify(queue: .main) {
//            self.todaySignals = .result(.init(
//                stepsOK: stepsOK,
//                sleepOK: sleepOK,
//                hrvOK: hrvOK,
//                rhrOK: rhrOK,
//                energyOK: energyOK
//            ))
//        }
//    }
//
//    private func hasTodayCumulative(_ id: HKQuantityTypeIdentifier, completion: @escaping (Bool) -> Void) {
//        guard let type = HKQuantityType.quantityType(forIdentifier: id) else {
//            completion(false)
//            return
//        }
//
//        let start = Calendar.current.startOfDay(for: Date())
//        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
//
//        let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
//            guard let sum = stats?.sumQuantity() else {
//                completion(false)
//                return
//            }
//
//            let value: Double
//            switch id {
//            case .activeEnergyBurned:
//                value = sum.doubleValue(for: .kilocalorie())
//            default:
//                value = sum.doubleValue(for: .count())
//            }
//
//            completion(value > 0)
//        }
//
//        hk.execute(query)
//    }
//
//    private func hasAnyQuantityLast24h(_ id: HKQuantityTypeIdentifier, completion: @escaping (Bool) -> Void) {
//        guard let type = HKQuantityType.quantityType(forIdentifier: id) else {
//            completion(false)
//            return
//        }
//
//        let end = Date()
//        let start = Calendar.current.date(byAdding: .hour, value: -24, to: end)!
//        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
//
//        let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, error in
//            // If access is denied, HealthKit often returns an error.
//            if error != nil { return completion(false) }
//            completion(!(samples ?? []).isEmpty)
//        }
//        hk.execute(q)
//    }
//
//    private func hasAnyCategoryLast24h(_ id: HKCategoryTypeIdentifier, completion: @escaping (Bool) -> Void) {
//        guard let type = HKCategoryType.categoryType(forIdentifier: id) else {
//            completion(false)
//            return
//        }
//
//        let end = Date()
//        let start = Calendar.current.date(byAdding: .hour, value: -24, to: end)!
//        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
//
//        let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, error in
//            if error != nil { return completion(false) }
//            completion(!(samples ?? []).isEmpty)
//        }
//        hk.execute(q)
//    }
//
//    // MARK: - Formatting
//
//    private func formatDateTime(_ d: Date) -> String {
//        let f = DateFormatter()
//        f.dateStyle = .medium
//        f.timeStyle = .short
//        return f.string(from: d)
//    }
//}
//
//// MARK: - Admin Unlock Sheet
//
//struct AdminUnlockSheet: View {
//    @Binding var password: String
//    let onCancel: () -> Void
//    let onUnlock: () -> Void
//
//    var body: some View {
//        NavigationView {
//            ZStack {
//                LinearGradient(
//                    colors: [
//                        Color.black,
//                        Color(red: 0.07, green: 0.08, blue: 0.12),
//                        Color(red: 0.10, green: 0.07, blue: 0.16)
//                    ],
//                    startPoint: .topLeading,
//                    endPoint: .bottomTrailing
//                )
//                .ignoresSafeArea()
//
//                VStack(spacing: 14) {
//                    VStack(alignment: .leading, spacing: 10) {
//                        HStack(spacing: 10) {
//                            Image(systemName: "lock.fill")
//                                .font(.system(size: 16, weight: .semibold))
//                                .foregroundStyle(.white.opacity(0.9))
//                                .padding(10)
//                                .background(.white.opacity(0.08))
//                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
//
//                            VStack(alignment: .leading, spacing: 2) {
//                                Text("Admin Access")
//                                    .font(.system(.headline, design: .rounded).weight(.semibold))
//                                    .foregroundColor(.white)
//                                Text("Enter password to open full app")
//                                    .font(.system(.subheadline, design: .rounded))
//                                    .foregroundColor(.white.opacity(0.65))
//                            }
//
//                            Spacer()
//                        }
//
//                        Divider().overlay(.white.opacity(0.12))
//
//                        SecureField("Password", text: $password)
//                            .textInputAutocapitalization(.never)
//                            .autocorrectionDisabled()
//                            .padding(12)
//                            .background(.white.opacity(0.06))
//                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
//                            .overlay(
//                                RoundedRectangle(cornerRadius: 14, style: .continuous)
//                                    .stroke(.white.opacity(0.10), lineWidth: 1)
//                            )
//                            .foregroundColor(.white)
//                    }
//                    .padding(16)
//                    .background(.white.opacity(0.06))
//                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
//                    .overlay(
//                        RoundedRectangle(cornerRadius: 18, style: .continuous)
//                            .stroke(.white.opacity(0.10), lineWidth: 1)
//                    )
//                    .padding(.horizontal, 16)
//                    .padding(.top, 12)
//
//                    HStack(spacing: 12) {
//                        Button {
//                            onCancel()
//                        } label: {
//                            Text("Cancel")
//                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
//                                .frame(maxWidth: .infinity)
//                                .padding(.vertical, 12)
//                                .background(.white.opacity(0.08))
//                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
//                        }
//                        .foregroundColor(.white.opacity(0.9))
//
//                        Button {
//                            onUnlock()
//                        } label: {
//                            Text("Unlock")
//                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
//                                .frame(maxWidth: .infinity)
//                                .padding(.vertical, 12)
//                                .background(.white.opacity(0.14))
//                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
//                        }
//                        .foregroundColor(.white)
//                    }
//                    .padding(.horizontal, 16)
//
//                    Spacer()
//                }
//            }
//            .navigationBarHidden(true)
//        }
//    }
//}
//
//// MARK: - Full App Tabs (Hook your existing pages here)
//
//struct FullTabView: View {
//    let onLockBack: () -> Void
//
//    var body: some View {
//        TabView {
//            BurnoutScoreView(steps: [])
//                .tabItem { Label("Home", systemImage: "gauge") }
//
//            ActivityView(steps: [])
//                .tabItem { Label("Activity", systemImage: "figure.walk") }
//
//            TrendsView(steps: [])
//                .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
//
//            SettingsView()
//                .tabItem { Label("Settings", systemImage: "gear") }
//        }
//        .overlay(alignment: .topTrailing) {
//            Button {
//                onLockBack()
//            } label: {
//                Image(systemName: "lock.open")
//                    .font(.system(size: 14, weight: .semibold))
//                    .foregroundColor(.white.opacity(0.85))
//                    .padding(10)
//                    .background(.black.opacity(0.35))
//                    .clipShape(Capsule())
//                    .padding(.trailing, 14)
//                    .padding(.top, 10)
//            }
//        }
//    }
//}
//
//// MARK: - Upload State (pilot UI)
//
//enum UploadState: String {
//    case ok
//    case pending
//    case failed
//
//    var title: String {
//        switch self {
//        case .ok: return "Data uploaded successfully"
//        case .pending: return "Upload pending"
//        case .failed: return "Upload failed"
//        }
//    }
//
//    var detail: String {
//        switch self {
//        case .ok: return "Your daily summaries are synced to the research server."
//        case .pending: return "We’ll upload automatically when internet is available."
//        case .failed: return "Please open the app on Wi-Fi or try again later."
//        }
//    }
//
//    var icon: String {
//        switch self {
//        case .ok: return "checkmark.icloud"
//        case .pending: return "icloud"
//        case .failed: return "exclamationmark.icloud"
//        }
//    }
//
//    var badgeText: String {
//        switch self {
//        case .ok: return "OK"
//        case .pending: return "PENDING"
//        case .failed: return "FAILED"
//        }
//    }
//
//    var badgeColor: Color {
//        switch self {
//        case .ok: return .green.opacity(0.9)
//        case .pending: return .orange.opacity(0.95)
//        case .failed: return .red.opacity(0.9)
//        }
//    }
//}
//
//// MARK: - Today Signals model
//
//enum TodaySignals {
//    case loading
//    case result(SignalsResult)
//
//    struct SignalsResult {
//        let stepsOK: Bool
//        let sleepOK: Bool
//        let hrvOK: Bool
//        let rhrOK: Bool
//        let energyOK: Bool
//
//        var collectedCount: Int {
//            [stepsOK, sleepOK, hrvOK, rhrOK, energyOK].filter { $0 }.count
//        }
//    }
//}
//
//// MARK: - Admin Password Verification
//
//private let ADMIN_PASSWORD_SHA256 = "be5557476d108b8a6b3aa860eed9b8598c6acea6b2307eeaccc24cb78b2c9c56"
//
//private func verifyAdminPassword(_ input: String) -> Bool {
//    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
//    guard !trimmed.isEmpty else { return false }
//    return sha256Hex(trimmed).lowercased() == ADMIN_PASSWORD_SHA256.lowercased()
//}
//
//private func sha256Hex(_ s: String) -> String {
//    let data = Data(s.utf8)
//    let digest = SHA256.hash(data: data)
//    return digest.map { String(format: "%02x", $0) }.joined()
//}
//
//// MARK: - Preview
//
//struct PilotLandingView_Previews: PreviewProvider {
//    static var previews: some View {
//        RootSwitcherView()
//            .preferredColorScheme(.dark)
//    }
//}
