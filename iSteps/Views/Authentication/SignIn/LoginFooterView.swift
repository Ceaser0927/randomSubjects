//
//  FooterView.swift
//  SwiftUI-LoginView
//
//  Created by Максим on 23.04.2020.
//  Copyright © 2020 Максим. All rights reserved.
//

import SwiftUI

struct LoginFooterView: View {
    
    fileprivate func createButton(title: String, imageName: String) -> some View {
        let isApple = (imageName.lowercased() == "apple")

        return Button(action: {}) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.20), lineWidth: 1)

                HStack(spacing: 10) {
                    Group {
                        if isApple {
                            Image(imageName)
                                .renderingMode(.template)   // ✅ 必须在 resizable 之前
                                .resizable()
                                .scaledToFit()
                                .frame(width: 22, height: 22)
                                .foregroundColor(.white.opacity(0.9)) // ✅ 只在 Apple 分支加
                        } else {
                            Image(imageName)
                                .renderingMode(.original)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 22, height: 22)
                        }
                    }

                    Text(title)
                        .font(.caption)
                        .bold()
                        .foregroundColor(.white.opacity(0.85))
                }
            }
        }
    }
    
    var body: some View {
        VStack {
            HStack {
                Rectangle()
                    .fill(Color.white.opacity(0.28))
                    .frame(height: 1)

                Text("OR")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.white.opacity(0.55))

                Rectangle()
                    .fill(Color.white.opacity(0.28))
                    .frame(height: 1)
            }
                .padding(.vertical, 5)
            HStack {
                createButton(title: "Google", imageName: "google")
                    .frame(height: 45, alignment: .center)
                    .buttonStyle(PlainButtonStyle())
                createButton(title: "Apple", imageName: "apple")
                    .frame(height: 45, alignment: .center)
                    .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

struct LoginFooterView_Previews: PreviewProvider {
    static var previews: some View {
        LoginFooterView()
    }
}
