//
//  ProfileOnboardingModule.swift
//  LastCallBeforeBurnout
//
//  A reusable onboarding module to collect Sex-at-birth + Age Range on first login.
//  - UI: Cosmic/dark friendly by default
//  - Storage: provides a Firestore helper, but you can also inject your own save handler
//

import SwiftUI

// MARK: - Enums (stored values are stable + ML-friendly)

public enum SexAtBirth: String, CaseIterable, Identifiable, Codable {
    case male
    case female
    case intersex
    case preferNotToSay = "prefer_not_to_say"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .male: return "Male"
        case .female: return "Female"
        case .intersex: return "Intersex"
        case .preferNotToSay: return "Prefer not to say"
        }
    }
}

public enum AgeRange: String, CaseIterable, Identifiable, Codable {
    case a18_24 = "18_24"
    case a25_34 = "25_34"
    case a35_44 = "35_44"
    case a45_54 = "45_54"
    case a55_64 = "55_64"
    case a65Plus = "65_plus"
    case preferNotToSay = "prefer_not_to_say"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .a18_24: return "18–24"
        case .a25_34: return "25–34"
        case .a35_44: return "35–44"
        case .a45_54: return "45–54"
        case .a55_64: return "55–64"
        case .a65Plus: return "65+"
        case .preferNotToSay: return "Prefer not to say"
        }
    }
}

// MARK: - Profile payload (what we store in Firestore)

public struct ParticipantProfilePayload: Codable {
    public var schemaVersion: Int
    public var sexAtBirth: String
    public var ageRange: String
    public var appVersion: String
    public var createdAtEpoch: Double
    public var updatedAtEpoch: Double

    public init(
        schemaVersion: Int = 1,
        sexAtBirth: SexAtBirth,
        ageRange: AgeRange,
        appVersion: String,
        createdAtEpoch: Double = Date().timeIntervalSince1970,
        updatedAtEpoch: Double = Date().timeIntervalSince1970
    ) {
        self.schemaVersion = schemaVersion
        self.sexAtBirth = sexAtBirth.rawValue
        self.ageRange = ageRange.rawValue
        self.appVersion = appVersion
        self.createdAtEpoch = createdAtEpoch
        self.updatedAtEpoch = updatedAtEpoch
    }

    public func asDictionary() -> [String: Any] {
        [
            "schemaVersion": schemaVersion,
            "sexAtBirth": sexAtBirth,
            "ageRange": ageRange,
            "appVersion": appVersion,
            "createdAtEpoch": createdAtEpoch,
            "updatedAtEpoch": updatedAtEpoch
        ]
    }
}

// MARK: - Firestore helper (optional)

#if canImport(FirebaseFirestore)
import FirebaseFirestore

public enum ProfileOnboardingFirestore {
    /// Writes/merges profile data into: participants/{uid}/profile_meta/profile
    public static func saveProfile(
        uid: String,
        payload: ParticipantProfilePayload,
        db: Firestore = Firestore.firestore(),
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let docRef = db.collection("participants").document(uid).collection("profile_meta").document("profile")

        var data = payload.asDictionary()
        data["updatedAt"] = FieldValue.serverTimestamp()
        data["createdAt"] = FieldValue.serverTimestamp()

        docRef.setData(data, merge: true) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
}
#endif

// MARK: - UI: Onboarding Card

public struct ProfileOnboardingView: View {
    public struct Copy {
        public var title: String = "Quick Setup"
        public var subtitle: String = "We collect this for research analysis. You can update it later."
        public var sexLabel: String = "Sex at birth"
        public var ageLabel: String = "Age range"
        public var continueButton: String = "Continue"
        public var skipButton: String = "Skip for now"
    }

    private let copy: Copy
    private let allowSkip: Bool
    private let onContinue: (_ sex: SexAtBirth, _ age: AgeRange) -> Void
    private let onSkip: (() -> Void)?

    // nil by default: user must make a selection
    @State private var sex: SexAtBirth? = nil
    @State private var age: AgeRange? = nil

    init(
        copy: Copy = Copy(),
        allowSkip: Bool = false,
        onContinue: @escaping (_ sex: SexAtBirth, _ age: AgeRange) -> Void,
        onSkip: (() -> Void)? = nil
    ) {
        self.copy = copy
        self.allowSkip = allowSkip
        self.onContinue = onContinue
        self.onSkip = onSkip
    }

    private var canContinue: Bool { sex != nil && age != nil }

    public var body: some View {
        ZStack {
            // Match PilotLandingView background gradient
            PilotMatchedBackground()

            VStack(spacing: 0) {
                // Header
                VStack(spacing: 10) {
                    Text(copy.title)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(copy.subtitle)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.top, 28)

                Spacer(minLength: 18)

                // Center-aligned pickers (INLINE dropdown, not sheet)
                VStack(spacing: 14) {
                    InlineDropdownRow(
                        title: copy.sexLabel,
                        valueText: sex?.displayName ?? "Select",
                        isSelected: sex != nil,
                        options: SexAtBirth.allCases,
                        current: sex,
                        display: { $0.displayName },
                        onSelect: { sex = $0 }
                    )

                    InlineDropdownRow(
                        title: copy.ageLabel,
                        valueText: age?.displayName ?? "Select",
                        isSelected: age != nil,
                        options: AgeRange.allCases,
                        current: age,
                        display: { $0.displayName },
                        onSelect: { age = $0 }
                    )
                }
                .frame(maxWidth: 520)
                .padding(.horizontal, 18)

                Spacer() // Push the actions to the bottom

                // Bottom actions
                VStack(spacing: 10) {
                    // 1) Continue turns bright blue ONLY when both selections are made
                    Button {
                        guard let sex, let age else { return }
                        onContinue(sex, age)
                    } label: {
                        Text(copy.continueButton)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(canContinue ? Color.cosmicBlue : Color.white.opacity(0.10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.white.opacity(canContinue ? 0.18 : 0.12), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .foregroundStyle(.white.opacity(canContinue ? 1.0 : 0.55))
                    }
                    .disabled(!canContinue)

                    if allowSkip, let onSkip = onSkip {
                        Button {
                            onSkip()
                        } label: {
                            Text(copy.skipButton)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.70))
                                .padding(.vertical, 8)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
        }
    }
}

// MARK: - UI: Flow wrapper (handles saving + loading state)

public struct ProfileOnboardingFlow: View {
    private let uid: String
    private let appVersion: String
    private let allowSkip: Bool
    private let onComplete: () -> Void
    private let onSkip: (() -> Void)?

    /// If you want to save somewhere else (not Firestore), provide this.
    /// If nil, Flow tries Firestore helper (if FirebaseFirestore is available).
    private let onSave: ((_ uid: String, _ payload: ParticipantProfilePayload, _ completion: @escaping (Result<Void, Error>) -> Void) -> Void)?

    @State private var isSaving: Bool = false
    @State private var errorMessage: String?

    public init(
        uid: String,
        appVersion: String,
        allowSkip: Bool = false,
        onComplete: @escaping () -> Void,
        onSkip: (() -> Void)? = nil,
        onSave: ((_ uid: String, _ payload: ParticipantProfilePayload, _ completion: @escaping (Result<Void, Error>) -> Void) -> Void)? = nil
    ) {
        self.uid = uid
        self.appVersion = appVersion
        self.allowSkip = allowSkip
        self.onComplete = onComplete
        self.onSkip = onSkip
        self.onSave = onSave
    }

    public var body: some View {
        ZStack {
            ProfileOnboardingView(
                allowSkip: allowSkip,
                onContinue: { sex, age in
                    save(sex: sex, age: age)
                },
                onSkip: {
                    onSkip?()
                }
            )

            if isSaving {
                SavingOverlay()
            }

            if let errorMessage = errorMessage {
                ErrorToast(message: errorMessage) {
                    withAnimation { self.errorMessage = nil }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private func save(sex: SexAtBirth, age: AgeRange) {
        isSaving = true
        errorMessage = nil

        let payload = ParticipantProfilePayload(
            sexAtBirth: sex,
            ageRange: age,
            appVersion: appVersion
        )

        // 1) Custom save handler if provided
        if let onSave = onSave {
            onSave(uid, payload) { result in
                handleSaveResult(result)
            }
            return
        }

        // 2) Default Firestore save if available
        #if canImport(FirebaseFirestore)
        ProfileOnboardingFirestore.saveProfile(uid: uid, payload: payload) { result in
            handleSaveResult(result)
        }
        #else
        // 3) No persistence configured
        handleSaveResult(.success(()))
        #endif
    }

    private func handleSaveResult(_ result: Result<Void, Error>) {
        DispatchQueue.main.async {
            self.isSaving = false
            switch result {
            case .success:
                self.onComplete()
            case .failure(let error):
                self.errorMessage = "Failed to save: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - UI Components

private struct LabeledPicker<Selection: Hashable, Content: View>: View {
    let title: String
    @Binding var selection: Selection
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))

            Menu {
                Picker(title, selection: $selection) {
                    content()
                }
            } label: {
                HStack {
                    Text(labelText())
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(Color.white.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func labelText() -> String {
        if let sex = selection as? SexAtBirth { return sex.displayName }
        if let age = selection as? AgeRange { return age.displayName }
        return String(describing: selection)
    }
}

private struct CosmicBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.06, blue: 0.12),
                    Color(red: 0.03, green: 0.03, blue: 0.07),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.07))
                .blur(radius: 50)
                .offset(x: -120, y: -180)

            Circle()
                .fill(Color.white.opacity(0.05))
                .blur(radius: 60)
                .offset(x: 140, y: 40)

            Circle()
                .fill(Color.white.opacity(0.04))
                .blur(radius: 70)
                .offset(x: -40, y: 220)

            StarsView(density: 70)
                .opacity(0.35)
        }
        .ignoresSafeArea()
    }
}

private struct StarsView: View {
    let density: Int

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                for _ in 0..<density {
                    let x = CGFloat.random(in: 0...size.width)
                    let y = CGFloat.random(in: 0...size.height)
                    let r = CGFloat.random(in: 0.6...1.8)
                    let alpha = CGFloat.random(in: 0.08...0.22)

                    let rect = CGRect(x: x, y: y, width: r, height: r)
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(.white.opacity(alpha))
                    )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
    }
}

private struct SavingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)

                Text("Saving…")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .background(Color.white.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .transition(.opacity)
    }
}

private struct ErrorToast: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.white.opacity(0.9))

                Text(message)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(2)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(8)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Spacer()
        }
        .ignoresSafeArea()
        .onTapGesture { onDismiss() }
    }
}

private struct PilotMatchedBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color.black,
                Color(red: 0.07, green: 0.08, blue: 0.12),
                Color(red: 0.10, green: 0.07, blue: 0.16)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

// MARK: - Inline dropdown row (expands options directly below the row)

private struct InlineDropdownRow<Option: Identifiable>: View {
    let title: String
    let valueText: String
    let isSelected: Bool
    let options: [Option]
    let current: Option?
    let display: (Option) -> String
    let onSelect: (Option) -> Void

    @State private var isOpen: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))

            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    isOpen.toggle()
                }
            } label: {
                HStack {
                    Text(valueText)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(isSelected ? 1.0 : 0.70))

                    Spacer()

                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(Color.white.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(isSelected ? 0.20 : 0.12), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(spacing: 0) {
                    ForEach(options) { option in
                        Button {
                            onSelect(option)
                            withAnimation(.easeOut(duration: 0.18)) {
                                isOpen = false
                            }
                        } label: {
                            HStack {
                                Text(display(option))
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.92))

                                Spacer()

                                if let current, current.id == option.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(Color.cosmicBlue)
                                }
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if option.id != options.last?.id {
                            Divider()
                                .background(Color.white.opacity(0.10))
                        }
                    }
                }
                .background(Color.black.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Row that looks like a picker but opens a sheet (kept for reference)

private struct SheetPickerRow: View {
    let title: String
    let valueText: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))

            Button(action: onTap) {
                HStack {
                    Text(valueText)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(isSelected ? 1.0 : 0.70))

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(Color.white.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(isSelected ? 0.20 : 0.12), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Generic selection sheet (dark friendly) (kept for reference)

private struct SelectionSheet<Option: Identifiable>: View {
    let title: String
    let options: [Option]
    let current: Option?
    let display: (Option) -> String
    let onSelect: (Option) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationView {
            List {
                ForEach(options) { option in
                    Button {
                        onSelect(option)
                    } label: {
                        HStack {
                            Text(display(option))
                            Spacer()
                            if let current, current.id == option.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black.opacity(0.9))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct ProfileOnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileOnboardingView(
            allowSkip: true,
            onContinue: { _, _ in },
            onSkip: {}
        )
        .preferredColorScheme(.dark)
    }
}
