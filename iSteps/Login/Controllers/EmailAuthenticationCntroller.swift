import SwiftUI
import FirebaseAuth

final class EmailAuthenticationController: ObservableObject {

    @Published var isLogin: Bool = false
    @Published var session: User? = nil

    // ✅ App 启动时调用：检查当前用户会话
    func initialSession() {
        let user = Auth.auth().currentUser
        session = user
        withAnimation {
            isLogin = (user != nil)
        }

        // 同步一下 app_mode（如果用户已经登录）
        if let email = user?.email?.lowercased(), email == "admin@test.com" {
            UserDefaults.standard.set(AppMode.full.rawValue, forKey: "app_mode")
        } else {
            UserDefaults.standard.set(AppMode.pilot.rawValue, forKey: "app_mode")
        }
    }

    // ✅ 登录：登录成功后务必更新 session / isLogin，并调用 handler
    func login(
        email: String,
        password: String,
        handler: @escaping (AuthDataResult?, Error?) -> Void
    ) {
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] result, error in
            guard let self else { return }

            // 先把结果回传给调用方（保留你原本设计）
            handler(result, error)

            if let error = error {
                print("Login failed:", error.localizedDescription)
                return
            }

            // ✅ 更新 session / isLogin（这一步是你之前“看起来没跳转”的关键）
            let user = result?.user
            self.session = user
            withAnimation {
                self.isLogin = (user != nil)
            }

            // ✅ 管理员判断只看 Firebase 返回的 user.email，不看你传进来的 email/password
            let signedInEmail = (user?.email ?? "").lowercased()
            if signedInEmail == "admin@test.com" {
                UserDefaults.standard.set(AppMode.full.rawValue, forKey: "app_mode")
            } else {
                UserDefaults.standard.set(AppMode.pilot.rawValue, forKey: "app_mode")
            }
        }
    }

    // ✅ 注册：注册成功后也更新 session / isLogin（否则注册完还在登录页）
    func createAccount(
        email: String,
        password: String,
        handler: @escaping (AuthDataResult?, Error?) -> Void
    ) {
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] result, error in
            guard let self else { return }

            handler(result, error)

            if let error = error {
                print("Create account failed:", error.localizedDescription)
                return
            }

            let user = result?.user
            self.session = user
            withAnimation {
                self.isLogin = (user != nil)
            }

            // 新注册的默认都走 pilot
            UserDefaults.standard.set(AppMode.pilot.rawValue, forKey: "app_mode")
        }
    }

    // ✅ 登出：退出后重置 session / isLogin + app_mode
    func logout() {
        do {
            try Auth.auth().signOut()
            session = nil
            withAnimation { isLogin = false }
            UserDefaults.standard.set(AppMode.pilot.rawValue, forKey: "app_mode")
        } catch {
            print("Logout failed:", error.localizedDescription)
        }
    }
}
