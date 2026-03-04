import SwiftUI
import FirebaseAuth

final class AuthManager: ObservableObject {
    @Published var user: User? = nil
    private var handle: AuthStateDidChangeListenerHandle?

    init() {
        handle = Auth.auth().addStateDidChangeListener { _, user in
            self.user = user
        }
    }

    deinit {
        if let handle { Auth.auth().removeStateDidChangeListener(handle) }
    }

    func signOut() {
        do { try Auth.auth().signOut() }
        catch { print("Sign out error: \(error.localizedDescription)") }
    }
}
