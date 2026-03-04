import SwiftUI
import HealthKit
import FirebaseFirestore
import FirebaseAuth

struct PilotLandingView: View {

    let onUnlock: () -> Void
    let studyTotalDays: Int = 14

    // ✅ 用项目现有的登录控制器驱动 UI 切换
    @EnvironmentObject var authController: EmailAuthenticationController

    // ✅ 统一用 AppStorage 让 SwiftUI 能即时刷新
    @AppStorage("app_mode") private var appModeRaw: String = AppMode.pilot.rawValue

    @AppStorage("participant_id") var participantId: String = ""
    @AppStorage("study_start_date") var studyStartDateEpoch: Double = 0

    @AppStorage("last_sync_epoch") var lastSyncEpoch: Double = 0
    @AppStorage("last_upload_epoch") var lastUploadEpoch: Double = 0
    @AppStorage("upload_state") var uploadStateRaw: String = PilotUploadState.ok.rawValue
    //@AppStorage("did_backfill_history") var didBackfillHistory: Bool = false
    
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

                    // Survey
                    Button {
                        isSurveyPresented = true
                    } label: {
                        Image(systemName: "doc.text")
                    }

                    // Admin unlock
                    Button {
                        showAdminSheet = true
                    } label: {
                        Image(systemName: "lock.circle")
                            .foregroundColor(.red) // Marked red: temporary access button
                    }

                    Button {
                        // Dismiss any presented UI before logging out
                        isSurveyPresented = false
                        showAdminSheet = false
                        adminPassword = ""
                        
                        // Reset app mode back to pilot before logout
                        appModeRaw = AppMode.pilot.rawValue
                        
                        // Trigger logout through authentication controller
                        authController.logout()
                        
                    } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .foregroundColor(.red) // Marked red: will be removed later
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
                        onUnlock() // Directly unlock without password (Pilot phase)
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
                //didBackfillHistory = false
                bootstrapStudyIfNeeded()
                upsertParticipantProfile()
                refreshAllStatuses()
                backfillLastDaysIfNeeded(days: 14)
            }
        }
    }
}

// MARK: - UI Composition

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
                    Text("Data collection dashboard")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.65))
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
        let day = studyDayIndex()
        let remaining = max(0, studyTotalDays - day)

        return glassCard(title: "Study Status", trailingIcon: "calendar") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    miniPill("Day \(day) / \(studyTotalDays)", icon: "flag.checkered")
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
                    value: healthAuthorized ? "Granted" : "Not Granted",
                    valueColor: healthAuthorized ? Color.green.opacity(0.9) : Color.red.opacity(0.9),
                    icon: "heart.fill"
                )

                statusRow(
                    title: "Watch",
                    value: watchLikelyConnected ? "Connected" : "Unknown",
                    valueColor: watchLikelyConnected ? Color.green.opacity(0.9) : Color.white.opacity(0.6),
                    icon: "applewatch"
                )

                statusRow(
                    title: "Last Sync",
                    value: lastSyncEpoch > 0 ? formatDateTime(Date(timeIntervalSince1970: lastSyncEpoch)) : "—",
                    valueColor: Color.white.opacity(0.85),
                    icon: "arrow.triangle.2.circlepath"
                )

                Button {
                    refreshAllStatuses()
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Sync Now")
                    }
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                }
                .foregroundColor(Color.white)

                Text("Tip: If Sleep/HRV is missing, wear your Apple Watch overnight and keep it charged.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.6))
            }
        }
    }

    var todaysDataCard: some View {
        glassCard(title: "Today’s Data", trailingIcon: "waveform.path.ecg") {
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

                    Divider().overlay(Color.white.opacity(0.12))

                    let collected = r.collectedCount
                    Text("Data completeness: \(collected) / 5 signals")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundColor(Color.white)

                    if collected < 4 {
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

        return glassCard(title: "Upload Status", trailingIcon: "icloud.and.arrow.up") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(st.title)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundColor(Color.white)
                    Spacer()
                    Text(st.badgeText)
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundColor(st.badgeColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }

                HStack {
                    Image(systemName: st.icon)
                        .foregroundColor(st.badgeColor.opacity(0.95))
                    Text(st.detail)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.65))
                }

                statusRow(
                    title: "Last Upload",
                    value: lastUploadEpoch > 0 ? formatDateTime(Date(timeIntervalSince1970: lastUploadEpoch)) : "—",
                    valueColor: Color.white.opacity(0.85),
                    icon: "clock"
                )

                Button {
                    uploadNowTapped()
                } label: {
                    HStack {
                        Image(systemName: "icloud.and.arrow.up")
                        Text("Upload Now")
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
}

#Preview {
    PilotLandingView(onUnlock: {})
        .preferredColorScheme(.dark)
}
