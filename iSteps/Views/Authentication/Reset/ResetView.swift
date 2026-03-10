import SwiftUI

struct ResetView: View {
    @Binding var presentedBinding: Bool
    @State private var showingPage = false

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

            VStack {
                if showingPage {
                    Successful(presentedBinding: $presentedBinding)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    ResetPasswordView(
                        presentedBinding: $presentedBinding,
                        presentSuccessfulMessage: {
                            withAnimation(.spring()) {
                                showingPage = true
                            }
                        }
                    )
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
        }
    }
}

struct ResetView_Previews: PreviewProvider {
    @State static var bool = true
    static var previews: some View {
        ResetView(presentedBinding: $bool)
    }
}
