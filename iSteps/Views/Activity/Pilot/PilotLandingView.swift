import SwiftUI
import HealthKit
import FirebaseFirestore
import FirebaseAuth
import SafariServices

struct PilotLandingView: View {

    let onUnlock: () -> Void
    let studyTotalDays: Int = 14

    @EnvironmentObject var authController: EmailAuthenticationController

    @AppStorage("app_mode") private var appModeRaw: String = AppMode.pilot.rawValue

    @AppStorage("participant_id") var participantId: String = ""
    @AppStorage("study_start_date") var studyStartDateEpoch: Double = 0

    @AppStorage("last_sync_epoch") var lastSyncEpoch: Double = 0
    @AppStorage("last_upload_epoch") var lastUploadEpoch: Double = 0
    @AppStorage("upload_state") var uploadStateRaw: String = PilotUploadState.ok.rawValue
    @AppStorage("irb_mode") private var isIRBMode = false

    @State var showAdminSheet = false
    @State var adminPassword = ""
    @State var showWrongPasswordAlert = false

    @State var isSurveyPresented = false

    let hk = HKHealthStore()

    @State var healthAuthorized: Bool = false
    @State var watchLikelyConnected: Bool = false
    @State var todaySignals: PilotTodaySignals = .loading

    @State var nextSurveyText: String = "Not scheduled"
    @State var surveyOverdue: Bool = false
    @State private var showProfileOnboarding = false
    @State private var saveError: String? = nil

    private let surveyURLString: String = "https://form.typeform.com/to/STFEkNs0"

    var body: some View {
        NavigationView {
            ZStack {
                pilotBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        headerCard
                        studyStatusCard
                        deviceStatusCard
                        todaysDataCard
                        surveyCard
                        uploadStatusCard

                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 90)
                }
            }
            .navigationTitle("Pilot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {

                    Button {
                        isSurveyPresented = true
                    } label: {
                        Image(systemName: "doc.text")
                    }
                    .accessibilityLabel("Survey")
                    .sheet(isPresented: $isSurveyPresented) {
                        if let url = URL(string: surveyURLString) {
                            SafariView(url: url)
                        } else {
                            NavigationView {
                                VStack(spacing: 12) {
                                    Text("Invalid survey link.")
                                        .font(.headline)
                                    Text(surveyURLString)
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 16)
                                    Button("Close") { isSurveyPresented = false }
                                }
                                .padding()
                                .navigationTitle("Survey")
                                .navigationBarTitleDisplayMode(.inline)
                            }
                        }
                    }

                    Button {
                        showAdminSheet = true
                    } label: {
                        Image(systemName: "lock.circle")
                            .foregroundColor(.red)
                    }
                    .accessibilityLabel("Admin Unlock")

                    Button {
                        isSurveyPresented = false
                        showAdminSheet = false
                        adminPassword = ""

                        appModeRaw = AppMode.pilot.rawValue
                        authController.logout()
                    } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .foregroundColor(.red)
                    }
                    .accessibilityLabel("Logout")
                }
            }
            .sheet(isPresented: $showAdminSheet) {
                AdminUnlockSheet(
                    password: $adminPassword,
                    onCancel: {
                        adminPassword = ""
                        showAdminSheet = false
                    },
                    onUnlock: {
                        adminPassword = ""
                        showAdminSheet = false
                        onUnlock()
                    }
                )
                .presentationDetents([.medium])
            }
            .alert("Incorrect password", isPresented: $showWrongPasswordAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Admin access denied.")
            }
            .onAppear {
                bootstrapStudyIfNeeded()
                upsertParticipantProfile()
                refreshAllStatuses()
                backfillLastDaysIfNeeded(days: 14)
                checkProfileNeedsOnboarding()
            }
        }
        .fullScreenCover(isPresented: $showProfileOnboarding) {
            ProfileOnboardingView(
                allowSkip: true,
                onContinue: { sex, age in
                    guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
                        saveError = "Not logged in."
                        return
                    }

                    let db = Firestore.firestore()

                    let data: [String: Any] = [
                        "uid": uid,
                        "sexAtBirth": sex.rawValue,
                        "ageRange": age.rawValue,
                        "schemaVersion": 1,
                        "updatedAt": FieldValue.serverTimestamp(),
                        "createdAt": FieldValue.serverTimestamp(),
                        "email": FieldValue.delete(),
                        "display": FieldValue.delete(),
                        "participantId": participantId
                    ]

                    db.collection("participants")
                        .document(uid)
                        .setData(data, merge: true) { err in
                            if let err = err {
                                saveError = err.localizedDescription
                                return
                            }
                            upsertParticipantProfile()
                            showProfileOnboarding = false
                        }
                },
                onSkip: {
                    showProfileOnboarding = false
                }
            )
        }
        .alert("Save failed", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }
}

extension PilotLandingView {

    var pilotBackground: some View {
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

    var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .padding(10)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Burnout Pilot Study")
                        .font(.system(.headline, design: .rounded).weight(.semibold))
                        .foregroundColor(Color.white)
                    Text(isIRBMode ? "IRB Demo Only" : "Data collection dashboard")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.65))
                    if isIRBMode {
                        Text("No real participant data is collected, displayed, or stored.")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundColor(.yellow.opacity(0.9))
                    }
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
                Text("Participant")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundColor(Color.white.opacity(0.6))
                Spacer()
                Text(participantId.isEmpty ? "Not set" : participantId)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundColor(Color.white)
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

    var studyStatusCard: some View {
        let day = isIRBMode ? 0 : studyDayIndex()
        let remaining = isIRBMode ? 0 : max(0, studyTotalDays - day)

        return glassCard(title: "Study Status", trailingIcon: "calendar") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    miniPill(isIRBMode ? "Demo Timeline" : "Day \(day) / \(studyTotalDays)", icon: "flag.checkered")
                    Spacer()
                    Text("\(remaining) days remaining")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.65))
                }

                Divider().overlay(Color.white.opacity(0.12))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Goal")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundColor(Color.white.opacity(0.6))
                    Text("Wear Apple Watch daily, especially overnight.")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundColor(Color.white)
                    Text("This app does not provide medical diagnosis.")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.6))
                }
            }
        }
    }

    var deviceStatusCard: some View {
        glassCard(title: "Device Status", trailingIcon: "applewatch") {
            VStack(spacing: 10) {

                statusRow(
                    title: "Health Access",
                    value: isIRBMode ? "Demo Only" : (healthAuthorized ? "Granted" : "Not Granted"),
                    valueColor: isIRBMode ? Color.white.opacity(0.85) : (healthAuthorized ? Color.green.opacity(0.9) : Color.red.opacity(0.9)),
                    icon: "heart.fill"
                )

                statusRow(
                    title: "Watch",
                    value: isIRBMode ? "Demo Only" : (watchLikelyConnected ? "Connected" : "Unknown"),
                    valueColor: isIRBMode ? Color.white.opacity(0.85) : (watchLikelyConnected ? Color.green.opacity(0.9) : Color.white.opacity(0.6)),
                    icon: "applewatch"
                )

                statusRow(
                    title: "Last Sync",
                    value: isIRBMode ? "Disabled" : (lastSyncEpoch > 0 ? formatDateTime(Date(timeIntervalSince1970: lastSyncEpoch)) : "—"),
                    valueColor: Color.white.opacity(0.85),
                    icon: "arrow.triangle.2.circlepath"
                )

                Button {
                    if !isIRBMode {
                        refreshAllStatuses()
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text(isIRBMode ? "Preview Demo" : "Sync Now")
                    }
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                }
                .foregroundColor(Color.white)

                Text(isIRBMode ? "Demo mode is enabled for IRB review." : "Tip: If Sleep, HRV, Respiratory, or Oxygen is missing, wear your Apple Watch overnight and keep it charged.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.6))
            }
        }
    }

    var todaysDataCard: some View {
        glassCard(title: "Today’s Data", trailingIcon: "waveform.path.ecg") {
            if isIRBMode {
                VStack(alignment: .leading, spacing: 10) {
                    demoDataCheckRow(name: "Steps")
                    demoDataCheckRow(name: "Sleep")
                    demoDataCheckRow(name: "HRV")
                    demoDataCheckRow(name: "Resting HR")
                    demoDataCheckRow(name: "Active Energy")
                    demoDataCheckRow(name: "Heart Rate")
                    demoDataCheckRow(name: "Respiratory")
                    demoDataCheckRow(name: "Oxygen")

                    Divider().overlay(Color.white.opacity(0.12))

                    Text("Data completeness: Demo only")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundColor(Color.white)

                    Text("All signal indicators are simulated for IRB review.")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.65))
                }
            } else {
                switch todaySignals {
                case .loading:
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Checking signals…")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(Color.white.opacity(0.8))
                    }

                case .result(let r):
                    VStack(alignment: .leading, spacing: 10) {
                        dataCheckRow(name: "Steps", ok: r.stepsOK)
                        dataCheckRow(name: "Sleep", ok: r.sleepOK)
                        dataCheckRow(name: "HRV", ok: r.hrvOK)
                        dataCheckRow(name: "Resting HR", ok: r.rhrOK)
                        dataCheckRow(name: "Active Energy", ok: r.energyOK)
                        dataCheckRow(name: "Heart Rate", ok: r.heartRateOK)
                        dataCheckRow(name: "Respiratory", ok: r.respiratoryOK)
                        dataCheckRow(name: "Oxygen", ok: r.oxygenOK)

                        Divider().overlay(Color.white.opacity(0.12))

                        let collected = r.collectedCount
                        Text("Data completeness: \(collected) / 8 signals")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundColor(Color.white)

                        if collected < 6 {
                            Text("Some signals are missing. This is common—please keep wearing your Apple Watch, especially overnight.")
                                .font(.system(.footnote, design: .rounded))
                                .foregroundColor(Color.white.opacity(0.65))
                        } else {
                            Text("Great—signals look good today.")
                                .font(.system(.footnote, design: .rounded))
                                .foregroundColor(Color.white.opacity(0.65))
                        }
                    }
                }
            }
        }
    }

    var surveyCard: some View {
        glassCard(title: "Survey", trailingIcon: "doc.text") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Next survey")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundColor(Color.white)
                    Spacer()
                    Text(nextSurveyText)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundColor(surveyOverdue ? Color.orange.opacity(0.95) : Color.white.opacity(0.85))
                }

                Text("You will be prompted when your study survey is available.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.6))

                Button {
                    isSurveyPresented = true
                } label: {
                    HStack {
                        Image(systemName: "square.and.pencil")
                        Text("Complete Survey")
                    }
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                }
                .foregroundColor(Color.white)
            }
        }
    }

    var uploadStatusCard: some View {
        let st = PilotUploadState(rawValue: uploadStateRaw) ?? .ok
        let uploadTitle = isIRBMode ? "Demo Mode: Upload Disabled" : st.title
        let uploadBadgeText = isIRBMode ? "DEMO" : st.badgeText
        let uploadBadgeColor = isIRBMode ? Color.orange.opacity(0.95) : st.badgeColor
        let uploadIcon = isIRBMode ? "slash.circle" : st.icon
        let uploadDetail = isIRBMode ? "No data is sent to the server in this mode." : st.detail
        let lastUploadText = isIRBMode ? "Disabled" : (lastUploadEpoch > 0 ? formatDateTime(Date(timeIntervalSince1970: lastUploadEpoch)) : "—")

        return glassCard(title: "Upload Status", trailingIcon: "icloud.and.arrow.up") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(uploadTitle)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundColor(Color.white)
                    Spacer()
                    Text(uploadBadgeText)
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundColor(uploadBadgeColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }

                HStack {
                    Image(systemName: uploadIcon)
                        .foregroundColor(uploadBadgeColor.opacity(0.95))
                    Text(uploadDetail)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.65))
                }

                statusRow(
                    title: "Last Upload",
                    value: lastUploadText,
                    valueColor: Color.white.opacity(0.85),
                    icon: "clock"
                )

                Button {
                    if !isIRBMode {
                        uploadNowTapped()
                    }
                } label: {
                    HStack {
                        Image(systemName: isIRBMode ? "slash.circle" : "icloud.and.arrow.up")
                        Text(isIRBMode ? "Disabled" : "Upload Now")
                    }
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                }
                .foregroundColor(Color.white)
            }
        }
    }

    private func checkProfileNeedsOnboarding() {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                checkProfileNeedsOnboarding()
            }
            return
        }

        Firestore.firestore()
            .collection("participants")
            .document(uid)
            .getDocument { snap, err in
                if let err = err {
                    print("Profile read error: \(err.localizedDescription)")
                    return
                }

                let data = snap?.data() ?? [:]
                let sex = (data["sexAtBirth"] as? String) ?? ""
                let age = (data["ageRange"] as? String) ?? ""

                if sex.isEmpty || age.isEmpty {
                    DispatchQueue.main.async {
                        showProfileOnboarding = true
                    }
                }
            }
    }
}

#Preview {
    PilotLandingView(onUnlock: {})
        .preferredColorScheme(.dark)
}
