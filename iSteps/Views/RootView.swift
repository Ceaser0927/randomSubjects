import SwiftUI
import FirebaseAuth

struct RootView: View {

    @EnvironmentObject private var session: EmailAuthenticationController

    // ✅ Session-only unlock: resets only when the app process is killed.
    @AppStorage("is_full_session_unlocked") private var isFullSessionUnlocked: Bool = false

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if session.isLogin {

                // ✅ Admin bypass: admin goes directly to AdminDashboardView
                if let email = Auth.auth().currentUser?.email,
                   email.lowercased() == "admin@test.com" {
                    AdminDashboardView()
                        .environmentObject(session)
                } else {

                    // ✅ Keep original pilot unlock flow unchanged
                    if isFullSessionUnlocked {
                        ContentView()
                    } else {
                        PilotLandingView(onUnlock: {
                            isFullSessionUnlocked = true
                        })
                        .environmentObject(session)
                    }
                }

            } else {
                LoginView(session: session)
                    .preferredColorScheme(.light)
            }
        }
        .onAppear {
            safeInitialSession()
        }
        .onChange(of: scenePhase) { phase in
            // ✅ Do NOT reset unlock state when returning from background.
            // isFullSessionUnlocked remains true while the app process is alive.
            switch phase {
            case .active:
                break
            case .inactive:
                break
            case .background:
                break
            @unknown default:
                break
            }
        }
    }

    private func safeInitialSession() {
        // ✅ Avoid Xcode Preview/Canvas issues.
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return
        }
        session.initialSession()
    }
}

#Preview {
    RootView()
}
