//
//  ResetPasswordView.swift
//  SwiftUI-LoginView
//
//  Created by Максим on 28.04.2020.
//  Copyright © 2020 Максим. All rights reserved.
//

import SwiftUI
import Firebase
import FirebaseAuth


struct ResetPasswordView: View {
    @State private var email = ""
    @State private var isShowingAlert = false
    @State private var errorMessage: String?
    @Binding var presentedBinding: Bool
    
    var presentSuccessfulMessage: (()->()) = {}
    
    fileprivate func resetPassword() {
        Auth.auth().sendPasswordReset(withEmail: self.email) { error in
            if error != nil {
                self.errorMessage = error?.localizedDescription
                self.isShowingAlert = true
                return
            }
            
            UIApplication.shared.endEditing()
            self.presentSuccessfulMessage()
        }
    }
    
    var body: some View {
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

            Spacer() // 把标题推到中间

            // Center: title + subtitle
            VStack(spacing: 10) {
                Text("Forgot Password?")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Enter the email address associated with your account")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer() // 把输入框/按钮推到底部

            // Bottom: input + button
            VStack(spacing: 18) {
                MinimalInputField(
                    text: $email,
                    placeholder: "Email",
                    systemImage: "envelope",
                    isSecure: false
                )

                Button(action: { resetPassword() }) {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.cosmicBlue)
                        .frame(height: 52)
                        .overlay(Text("Reset").foregroundColor(.white).bold())
                }
                .alert(isPresented: $isShowingAlert) {
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

struct ResetPasswordView_Previews: PreviewProvider {
    @State static var presentedBinding = false
    static var previews: some View {
        ResetPasswordView(presentedBinding: $presentedBinding)
    }
}
