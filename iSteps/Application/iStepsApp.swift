import SwiftUI
import FirebaseCore
import FirebaseAuth

@main
struct iStepsApp: App {
    @StateObject private var authController = EmailAuthenticationController()

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authController)
        }
    }
}
