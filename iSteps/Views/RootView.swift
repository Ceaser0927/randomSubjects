import SwiftUI

struct RootView: View {

    @StateObject var session = EmailAuthenticationController()

    var body: some View {

        Group {
            if session.isLogin {
                ContentView()
            } else {
                LoginView(session: session).preferredColorScheme(.light)
            }
        }
        .onAppear {
            session.initialSession()
        }
    }
}
#Preview {
    RootView()
}
