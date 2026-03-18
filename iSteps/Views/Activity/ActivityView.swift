//
//  ActivityView.swift
//  iSteps
//
//  Modernized AI-style dashboard
//

import SwiftUI
import HealthKit
import SafariServices

struct ActivityView: View {

    var steps: [Step]

    @State private var isShareViewPresented = false
    @State private var isSurveyPresented = false

    // MARK: - Aggregates
    var totalSteps: Int {
        steps.map { $0.count }.reduce(0, +)
    }

    var totalCalories: Int {
        totalSteps / 20
    }

    var totalDistance: Double {
        Double(totalSteps) / 2000.0
    }

    private var hasData: Bool { totalSteps > 0 }

    // MARK: - Share text
    var sharedTextDetailed: String {
        var sharedText =
        """
        🚶 Total Steps: \(totalSteps)
        🏃 Distance: \(String(format: "%.1f", totalDistance)) km
        🔥 Calories: \(totalCalories) kcal
        """

        sharedText.append(
        """
        \n________________\n
        Sent with iSteps❤️
        """
        )
        return sharedText
    }

    var body: some View {
        NavigationView {
            ZStack {
                // Background similar to your Score page
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

                        headerCard

                        if hasData {
                            // Metrics grid (2x2)
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                metricCard(
                                    title: "Steps / Week",
                                    value: "\(totalSteps)",
                                    subtitle: "Sum of available days",
                                    icon: "figure.step.training"
                                )

                                metricCard(
                                    title: "Calories / Week",
                                    value: "\(totalCalories)",
                                    subtitle: "Estimated burn",
                                    icon: "flame"
                                )

                                metricCard(
                                    title: "Distance / Week",
                                    value: "\(String(format: "%.1f", totalDistance)) km",
                                    subtitle: "Approx. walking",
                                    icon: "figure.walk"
                                )

                                metricCard(
                                    title: "Water (Cup)",
                                    value: "7",
                                    subtitle: "Manual placeholder",
                                    icon: "drop"
                                )
                            }

                            // Graph card
                            glassCard(title: "Trend", trailingIcon: "chart.xyaxis.line") {
                                GraphView(steps: steps)
                                    .frame(minHeight: 180)
                            }

                        } else {
                            // No data state
                            glassCard(title: "Awaiting sync", trailingIcon: "waveform.path.ecg") {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("No activity data yet.")
                                        .font(.system(.headline, design: .rounded).weight(.semibold))
                                        .foregroundColor(.white)

                                    Text("Connect Apple Watch & allow Health access to see your weekly activity and trends here.")
                                        .font(.system(.subheadline, design: .rounded))
                                        .foregroundColor(.white.opacity(0.65))

                                    HStack(spacing: 10) {
                                        pill("HealthKit", icon: "heart.fill")
                                        pill("Watch", icon: "applewatch")
                                        pill("Weekly", icon: "calendar")
                                    }
                                    .padding(.top, 4)
                                }
                                .padding(.vertical, 6)
                            }
                        }

                        Spacer(minLength: 18)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    // 避免被底部 tab/自定义底栏挡住（你底部看起来有一条 bar）
                    .padding(.bottom, 90)
                }
            }
            .navigationTitle("Fitness")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {

//                    Button {
//                        isSurveyPresented = true
//                    } label: {
//                        Image(systemName: "doc.text")
//                    }
//                    .sheet(isPresented: $isSurveyPresented) {
//                        SafariView(url: URL(string: "https://form.typeform.com/to/STFEkNs0")!)
//                    }

                    Button {
                        isShareViewPresented = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .sheet(isPresented: $isShareViewPresented) {
                        ShareViewController(activityItems: [sharedTextDetailed])
                    }
                }
            }
        }
    }

    // MARK: - Header card
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
                    Text("Activity Dashboard")
                        .font(.system(.headline, design: .rounded).weight(.semibold))
                        .foregroundColor(.white)
                    Text("\(Date(), formatter: Date.dateFormatter(string: "EEEE, d MMM"))")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(.white.opacity(0.65))
                }

                Spacer()

                Text(hasData ? "READY" : "NO DATA")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundColor(hasData ? .green.opacity(0.9) : .white.opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.08))
                    .clipShape(Capsule())
            }

            Divider().overlay(.white.opacity(0.12))

            if hasData {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Weekly summary")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundColor(.white.opacity(0.6))
                        Text("\(totalSteps) steps • \(String(format: "%.1f", totalDistance)) km")
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Est. burn")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundColor(.white.opacity(0.6))
                        Text("\(totalCalories) kcal")
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .foregroundColor(.white)
                    }
                }
            } else {
                Text("Sync to unlock weekly metrics + trends.")
                    .font(.system(.subheadline, design: .rounded))
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

    // MARK: - Metric cards
    private func metricCard(title: String, value: String, subtitle: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 32, height: 32)
                    .background(.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.25))
            }

            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundColor(.white.opacity(0.9))

            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundColor(.white)

            Text(subtitle)
                .font(.system(.footnote, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
    }

    // MARK: - Glass card wrapper
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
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
    }

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
}

struct ActivityView_Previews: PreviewProvider {
    static var previews: some View {
        ActivityView(steps: [])
            .preferredColorScheme(.dark)
    }
}

// Safari wrapper (kept)
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) { }
}
