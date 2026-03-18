import SwiftUI
import HealthKit
import UserNotifications
import SafariServices

struct SettingsView: View {

    @State private var notificationsEnabled = false
    @State private var healthAuthorized = false
    @State private var showingPrivacy = false
    @State private var showingFeedback = false

    private let healthStore = HKHealthStore()

    var body: some View {
        NavigationView {
            ZStack {
                // Background (same style as other pages)
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

                ScrollView {
                    VStack(spacing: 14) {

                        headerCard

                        // Notifications
                        glassCard(title: "Notifications", icon: "bell") {
                            Toggle(isOn: $notificationsEnabled) {
                                Text("Strain alerts")
                                    .foregroundColor(.white)
                            }
                            .tint(.green)
                            .onChange(of: notificationsEnabled) { value in
                                if value {
                                    requestNotificationPermission()
                                }
                            }

                            Text("Receive gentle alerts when strain increases.")
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.6))
                        }

                        // Health Data
                        glassCard(title: "Health Data", icon: "heart.fill") {
                            HStack {
                                Text("Apple Health Access")
                                    .foregroundColor(.white)
                                Spacer()
                                Text(healthAuthorized ? "Connected" : "Not Connected")
                                    .foregroundColor(healthAuthorized ? .green : .red)
                            }

                            Button {
                                requestHealthAccess()
                            } label: {
                                Text("Request Access")
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Color.white.opacity(0.08))
                                    .clipShape(Capsule())
                            }
                            .foregroundColor(.white)

                            Text("We only read activity data locally. No data is uploaded.")
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.6))
                        }

                        // Privacy & Legal
                        glassCard(title: "Privacy & Legal", icon: "lock.shield") {
                            Button {
                                showingPrivacy = true
                            } label: {
                                settingsRow(title: "Privacy Policy", icon: "doc.text")
                            }

                            Text("This app is not a medical device and does not provide medical diagnosis.")
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.6))
                        }

                        // Feedback
                        glassCard(title: "Feedback", icon: "bubble.left.and.bubble.right") {
                            Button {
                                showingFeedback = true
                            } label: {
                                settingsRow(title: "Send Feedback", icon: "paperplane")
                            }

                            Text("Help us improve during the pilot phase.")
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.6))
                        }

                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 80)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                checkHealthAuthorization()
            }
            .sheet(isPresented: $showingPrivacy) {
                SafariView(url: URL(string: "https://your-privacy-link.com")!)
            }
            .sheet(isPresented: $showingFeedback) {
                SafariView(url: URL(string: "https://form.typeform.com/to/YOUR_FORM_ID")!)
            }
        }
    }

    // MARK: - Components

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(10)
                    .background(.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Settings")
                        .font(.system(.headline, design: .rounded).weight(.semibold))
                        .foregroundColor(.white)

                    Text("Manage notifications, data, and privacy.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(.white.opacity(0.65))
                }

                Spacer()
            }

            Divider().overlay(.white.opacity(0.12))
        }
        .padding(16)
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func glassCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: icon)
                    .foregroundColor(.white)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                Spacer()
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

    private func settingsRow(title: String, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .foregroundColor(.white)
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(.white.opacity(0.4))
        }
    }

    // MARK: - Permissions

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func requestHealthAccess() {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let typesToRead: Set = [
            HKQuantityType.quantityType(forIdentifier: .stepCount)!
        ]

        healthStore.requestAuthorization(toShare: [], read: typesToRead) { success, _ in
            DispatchQueue.main.async {
                healthAuthorized = success
            }
        }
    }

    private func checkHealthAuthorization() {
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKQuantityType.quantityType(forIdentifier: .stepCount)
        else { return }

        let status = healthStore.authorizationStatus(for: type)
        healthAuthorized = (status == .sharingAuthorized)
    }
}
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .preferredColorScheme(.dark)
    }
}
