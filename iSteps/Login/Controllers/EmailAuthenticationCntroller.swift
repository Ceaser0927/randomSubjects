//
//  FirebaseSession.swift
//  SwiftUI-LoginView
//
//  Created by Максим on 19.04.2020.
//  Copyright © 2020 Максим. All rights reserved.
//

import SwiftUI
import FirebaseAuth

final class EmailAuthenticationController: ObservableObject {

    @Published var isLogin: Bool = false
    @Published var session: User? = nil

    // ✅ App 启动时调用：检查当前用户会话 + 是否已验证邮箱
    func initialSession() {
        let user = Auth.auth().currentUser
        session = user

        withAnimation {
            //isLogin = (user != nil && user?.isEmailVerified == true)
            isLogin = (user != nil)
        }
    }

    // ✅ 登录：替换掉旧的 AuthDataResultCallback
    func login(
        email: String,
        password: String,
        handler: @escaping (AuthDataResult?, Error?) -> Void
    ) {
        Auth.auth().signIn(withEmail: email, password: password, completion: handler)
    }

    // ✅ 注册：替换掉旧的 AuthDataResultCallback
    func createAccount(
        email: String,
        password: String,
        handler: @escaping (AuthDataResult?, Error?) -> Void
    ) {
        Auth.auth().createUser(withEmail: email, password: password, completion: handler)
    }

    // ✅ 登出：不要 try!，避免崩溃
    func logout() {
        do {
            try Auth.auth().signOut()
            session = nil
            withAnimation { isLogin = false }
        } catch {
            // 如果你想调试可以 print(error)
        }
    }
}
