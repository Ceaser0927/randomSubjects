//
//  RegistrationView.swift
//  SwiftUI-LoginView
//
//  Created by Максим on 21.04.2020.
//  Copyright © 2020 Максим. All rights reserved.
//

import SwiftUI
import Firebase
import FirebaseAuth


struct RegistrationPageView: View {
    @Binding var presentedBinding: Bool
    @ObservedObject var session: EmailAuthenticationController
    
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    
    @State private var errorMessage: String?
    @State private var showingAlert = false
    
    fileprivate func registration() {
        if password != confirmPassword {
            self.errorMessage = "Password mismatch!"
            self.showingAlert = true
            return
        }
        session.createAccount(email: email, password: password) { user, error in
            if error != nil {
                self.errorMessage = error?.localizedDescription
                self.showingAlert = true
                return
            }
            
            Auth.auth().currentUser?.sendEmailVerification(completion: { error in
                
            })
            
            UIApplication.shared.endEditing()
        }
    }
    
    var body: some View {
        ZStack {
            SpaceMeteorFieldView()
                .ignoresSafeArea()
                .overlay(
                    RadialGradient(
                        colors: [Color.clear, Color.black.opacity(0.55)],
                        center: .center,
                        startRadius: 120,
                        endRadius: 520
                    )
                    .ignoresSafeArea()
                )

            VStack(spacing: 0) {

                // Top bar
                HStack {
                    Spacer()
                    Button("Cancel") {
                        presentedBinding = false
                    }
                    .foregroundColor(.cosmicBlue)
                    .font(.footnote.weight(.semibold))
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)

                Spacer() // 标题居中

                // Center: title + subtitle
                VStack(spacing: 10) {
                    Text("Create Account")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("Sign up with your email to get started")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer() // 输入区到底部

                // Bottom: inputs + button
                VStack(spacing: 16) {
                    MinimalInputField(
                        text: $email,
                        placeholder: "Email",
                        systemImage: "envelope",
                        isSecure: false
                    )

                    MinimalInputField(
                        text: $password,
                        placeholder: "Password",
                        systemImage: "lock",
                        isSecure: true
                    )

                    MinimalInputField(
                        text: $confirmPassword,
                        placeholder: "Confirm Password",
                        systemImage: "lock",
                        isSecure: true
                    )

                    Button(action: { registration() }) {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.cosmicBlue)
                            .frame(height: 52)
                            .overlay(Text("Continue").foregroundColor(.white).bold())
                    }
                    .alert(isPresented: $showingAlert) {
                        Alert(
                            title: Text("Error"),
                            message: Text(errorMessage ?? "Unknown error"),
                            dismissButton: .default(Text("OK"))
                        )
                    }
                }
                .padding(.horizontal, 34)
                .padding(.bottom, 28)
            }
            .keyboardAdaptive()
        }
    }
}

struct RegistrationPageView_Previews: PreviewProvider {
    @State static var previewPresented = false
    @ObservedObject static var session = EmailAuthenticationController()
    static var previews: some View {
        RegistrationPageView(presentedBinding: $previewPresented, session: self.session)
    }
}
