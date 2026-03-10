import SwiftUI
import Firebase
import Combine

struct LoginView: View {

    @ObservedObject var session: EmailAuthenticationController
    @State private var email = ""
    @State private var password = ""
    @State private var presentedPasswordReset = false

    var body: some View {
        ZStack {
            // MARK: - True space meteor shower background (twinkling stars + random meteors)
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

            VStack(alignment: .center, spacing: 22) {

                Spacer(minLength: 44)

                // MARK: - Title (bigger, consistent with dark main page)
                VStack(spacing: 10) {
                    //HandwrittenHelloGlass(text: "Hello")
                    HandwriteGlassLoopTitle(
                        lines: ["Hello", "Nice to meet you!"],
                        fontName: "Chalkboard SE",
                        fontSize: 56,
                        writeDuration: 4.2,   // 写字速度
                        holdDuration: 1.5   // 停留时间
                    )
                    .frame(height: 110)
                    .offset(y: -90)
                }

                // MARK: - Inputs (no container box)
                VStack(spacing: 18) {
                    MinimalInputField(
                        text: $email,
                        placeholder: "Email",
                        systemImage: "envelope",
                        isSecure: false
                    )

                    VStack(alignment: .trailing, spacing: 8) {
                        MinimalInputField(
                            text: $password,
                            placeholder: "Password",
                            systemImage: "lock",
                            isSecure: true
                        )

                        Button {
                            presentedPasswordReset = true
                        } label: {
                            Text("Forgot password?")
                                .foregroundColor(.cosmicBlue)
                        }
                        .sheet(isPresented: $presentedPasswordReset) {
                            ResetView(presentedBinding: $presentedPasswordReset)
                        }
                    }
                }
                .padding(.horizontal, 34)
                .padding(.top, 6)

                // MARK: - Keep your existing buttons component
                // IMPORTANT: This prevents Google/Apple duplication and restores "No account? Sign Up".
                LoginButtons(
                    session: session,
                    bindEmail: $email,
                    bindPassword: $password
                )
                .padding(.horizontal, 34)
                .padding(.top, 6)
                .tint(Color(red: 0.20, green: 0.72, blue: 1.0)) // bright blue
                .accentColor(Color(red: 0.20, green: 0.72, blue: 1.0)) // for older iOS
                Spacer(minLength: 0)
                // MARK: - Footer (keep your existing layout)
                LoginFooterView()
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 18)
                    .foregroundColor(.white.opacity(0.55))
            }
            // Use your existing keyboard behavior (you already had this in the original template)
            .keyboardAdaptive()
        }
    }
}

// MARK: - Minimal input field with high-contrast placeholder (no box)
struct MinimalInputField: View {
    @Binding var text: String
    var placeholder: String
    var systemImage: String
    var isSecure: Bool = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundColor(.white.opacity(0.80))
                    .frame(width: 22)

                ZStack(alignment: .leading) {
                    // Custom placeholder (brighter than default)
                    if text.isEmpty {
                        Text(placeholder)
                            .foregroundColor(.white.opacity(0.55))
                            .font(.system(size: 16, weight: .regular))
                    }

                    if isSecure {
                        SecureField("", text: $text)
                            .foregroundColor(.white.opacity(0.92))
                            .font(.system(size: 16, weight: .regular))
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                    } else {
                        TextField("", text: $text)
                            .foregroundColor(.white.opacity(0.92))
                            .font(.system(size: 16, weight: .regular))
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .keyboardType(placeholder.lowercased().contains("email") ? .emailAddress : .default)
                    }
                }
            }

            // Stronger underline for visibility
            Rectangle()
                .fill(Color.white.opacity(0.28))
                .frame(height: 1)
        }
    }
}

//
// MARK: - Background: twinkling stars + random meteors from all edges
//

struct SpaceMeteorFieldView: View {

    @State private var meteors: [MeteorParticle] = []
    @State private var nextSpawnTime: TimeInterval = 0

    private let starSeed: UInt64 = 20260309

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in

                // MARK: - Background gradient
                let rect = Path(CGRect(origin: .zero, size: size))
                context.fill(
                    rect,
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(red: 0.02, green: 0.03, blue: 0.06),
                            Color(red: 0.04, green: 0.05, blue: 0.10)
                        ]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: size.width, y: size.height)
                    )
                )

                // MARK: - Twinkling stars
                drawTwinklingStars(context: &context, size: size, time: t)

                // MARK: - Meteors
                drawMeteors(context: &context, size: size, time: t)
            }
            .onAppear {
                // Spawn soon after appearing
                nextSpawnTime = t + Double.random(in: 0.2...0.6)
            }
            .task {
                // No-op; keeps lifecycle predictable on older systems
            }
            .overlay(
                // Drive spawning & cleanup without onChange (compatible)
                Color.clear.onAppear { }
                    .onReceive(Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()) { _ in
                        // Just keeping state alive; actual spawn/cleanup is done below in Canvas tick
                    }
            )
            .background(
                // Spawn & cleanup executed every Timeline tick via a view update
                SpawnDriverView(
                    time: t,
                    nextSpawnTime: $nextSpawnTime,
                    meteors: $meteors
                )
            )
        }
    }

    // MARK: - Stars drawing
    private func drawTwinklingStars(context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        var rng = SeededGenerator(seed: starSeed)
        let starCount = 220

        for i in 0..<starCount {
            let x = Double.random(in: 0...size.width, using: &rng)
            let y = Double.random(in: 0...size.height, using: &rng)
            let r = Double.random(in: 0.4...1.7, using: &rng)

            let phase = Double.random(in: 0...(2 * .pi), using: &rng)
            let speed = Double.random(in: 0.7...2.2, using: &rng)
            let base = Double.random(in: 0.16...0.46, using: &rng)

            let twinkle = base + 0.30 * (0.5 + 0.5 * sin(time * speed + phase))
            let alpha = min(0.78, max(0.06, twinkle))

            let rect = CGRect(x: x, y: y, width: r, height: r)
            context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(alpha)))

            if i % 10 == 0 {
                let glowRect = CGRect(x: x - r * 1.2, y: y - r * 1.2, width: r * 3.6, height: r * 3.6)
                context.fill(Path(ellipseIn: glowRect), with: .color(Color.white.opacity(alpha * 0.18)))
            }
        }
    }

    // MARK: - Meteors drawing
    private func drawMeteors(context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        for m in meteors {
            let p = m.progress(at: time)
            if p < 0 || p > 1 { continue }

            let x = m.start.x + (m.end.x - m.start.x) * p
            let y = m.start.y + (m.end.y - m.start.y) * p

            let dx = m.end.x - m.start.x
            let dy = m.end.y - m.start.y
            let len = max(1, sqrt(dx*dx + dy*dy))
            let ux = dx / len
            let uy = dy / len

            let head = CGPoint(x: x, y: y)
            let tailEnd = CGPoint(x: x - ux * m.tailLength, y: y - uy * m.tailLength)

            var path = Path()
            path.move(to: head)
            path.addLine(to: tailEnd)

            let alpha = max(0.0, 1.0 - p) * 0.95

            context.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [
                        Color.white.opacity(alpha),
                        Color.white.opacity(alpha * 0.16),
                        Color.white.opacity(0.0)
                    ]),
                    startPoint: head,
                    endPoint: tailEnd
                ),
                lineWidth: m.thickness
            )

            context.stroke(
                path,
                with: .color(Color.white.opacity(alpha * 0.18)),
                style: StrokeStyle(lineWidth: m.thickness * 3, lineCap: .round)
            )
        }
    }
}

// MARK: - Spawning driver (keeps old SwiftUI compatible)
private struct SpawnDriverView: View {
    let time: TimeInterval
    @Binding var nextSpawnTime: TimeInterval
    @Binding var meteors: [MeteorParticle]

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { step(size: geo.size) }
                .onChangeCompat(of: time) { _ in
                    step(size: geo.size)
                }
        }
    }

    private func step(size: CGSize) {
        // Spawn meteor occasionally
        if time >= nextSpawnTime {
            meteors.append(MeteorParticle.randomSpawn(time: time, canvasSize: size))
            nextSpawnTime = time + Double.random(in: 0.6...1.6)
        }
        // Cleanup finished
        meteors.removeAll { $0.progress(at: time) >= 1.0 }
    }
}

// MARK: - Compatibility onChange (works on older SwiftUI)
private extension View {
    func onChangeCompat<T: Equatable>(of value: T, _ action: @escaping (T) -> Void) -> some View {
        if #available(iOS 17.0, *) {
            return self.onChange(of: value) { _, newValue in action(newValue) }
        } else {
            return self.onChange(of: value) { newValue in action(newValue) }
        }
    }
}

// MARK: - Meteor model
struct MeteorParticle: Identifiable {
    let id = UUID()
    let start: CGPoint
    let end: CGPoint
    let startTime: TimeInterval
    let duration: TimeInterval
    let tailLength: CGFloat
    let thickness: CGFloat

    func progress(at time: TimeInterval) -> CGFloat {
        CGFloat((time - startTime) / duration)
    }

    static func randomSpawn(time: TimeInterval, canvasSize: CGSize) -> MeteorParticle {
        let w = canvasSize.width
        let h = canvasSize.height
        let margin: CGFloat = 80

        let edge = Int.random(in: 0...3)
        let start: CGPoint
        let end: CGPoint

        switch edge {
        case 0: // top -> bottom-ish
            start = CGPoint(x: CGFloat.random(in: -margin...(w+margin)), y: -margin)
            end = CGPoint(x: CGFloat.random(in: -margin...(w+margin)), y: h + margin)
        case 1: // bottom -> top-ish
            start = CGPoint(x: CGFloat.random(in: -margin...(w+margin)), y: h + margin)
            end = CGPoint(x: CGFloat.random(in: -margin...(w+margin)), y: -margin)
        case 2: // left -> right-ish
            start = CGPoint(x: -margin, y: CGFloat.random(in: -margin...(h+margin)))
            end = CGPoint(x: w + margin, y: CGFloat.random(in: -margin...(h+margin)))
        default: // right -> left-ish
            start = CGPoint(x: w + margin, y: CGFloat.random(in: -margin...(h+margin)))
            end = CGPoint(x: -margin, y: CGFloat.random(in: -margin...(h+margin)))
        }

        return MeteorParticle(
            start: start,
            end: end,
            startTime: time + Double.random(in: 0.0...0.5),
            duration: Double.random(in: 0.9...1.6),
            tailLength: CGFloat.random(in: 220...360),
            thickness: CGFloat.random(in: 1.6...2.6)
        )
    }
}

// MARK: - Seeded RNG
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = 6364136223846793005 &* state &+ 1442695040888963407
        return state
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView(session: EmailAuthenticationController())
            .preferredColorScheme(.dark)
            .previewDevice("iPhone 14 Pro")
    }
}
extension Color {
    static let cosmicBlue = Color(red: 0.20, green: 0.72, blue: 1.0)
}

struct HandwriteGlassLoopTitle: View {
    let lines: [String]
    var fontName: String = "Apple Chancery"   // 可换 "Apple Chancery"
    var fontSize: CGFloat = 72

    var writeDuration: Double = 4.2
    var holdDuration: Double = 1.5
    var restartDelay: Double = 0.25

    @State private var index: Int = 0
    @State private var progress: CGFloat = 0
    @State private var penJitter: CGFloat = 0
    @State private var shimmer: CGFloat = -0.8

    var body: some View {
        let text = lines.isEmpty ? "" : lines[index]

        ZStack {
            // 底层淡雾（玻璃底）
            Text(text)
                .font(.custom(fontName, size: fontSize))
                .foregroundColor(.white.opacity(0.10))
                .blur(radius: 0.3)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 24)

            // 主体：写字遮罩 + 玻璃高光
            Text(text)
                .font(.custom(fontName, size: fontSize))
                .foregroundColor(.white.opacity(0.80))
                .overlay(glassHighlight.mask(Text(text).font(.custom(fontName, size: fontSize))))
                .mask(writeMask) // 关键：像写出来
                .shadow(color: .white.opacity(0.22), radius: 18, x: 0, y: 10)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 24)

            // 笔尖光点（沿着遮罩前沿走）
            penTip
        }
        .onAppear { startLoop() }
    }

    // 写字遮罩：从左到右推进 + 边缘柔化 + 轻微抖动（更像笔迹）
    private var writeMask: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let frontX = max(0, min(w, w * progress + penJitter))

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.black)
                    .frame(width: frontX, height: h)
                    .blur(radius: 0.9)

                // 前沿的“墨迹扩散”感
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.black, Color.black.opacity(0.0)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 34, height: h)
                    .offset(x: frontX - 17)
                    .blur(radius: 2.6)
                    .opacity(progress < 1 ? 1 : 0)
            }
        }
    }

    // 玻璃高光 + 扫光
    private var glassHighlight: some View {
        LinearGradient(
            colors: [
                Color.white.opacity(0.95),
                Color.white.opacity(0.38),
                Color.white.opacity(0.85)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            GeometryReader { geo in
                LinearGradient(
                    colors: [.clear, .white.opacity(0.55), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: 90)
                .rotationEffect(.degrees(18))
                .offset(x: shimmer * geo.size.width)
                .blendMode(.screen)
            }
        )
    }

    // 笔尖：一个小亮点 + 柔光
    private var penTip: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            // 笔尖大概在文字中线偏上（看起来更像在写）
            let y = h * 0.55
            let x = max(0, min(w, w * progress + penJitter))

            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 4, height: 4)
                    .position(x: x, y: y)

                Circle()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 22, height: 22)
                    .blur(radius: 1.5)
                    .position(x: x, y: y)
            }
            .opacity(progress < 1 ? 1 : 0) // 写完隐藏笔尖
        }
    }

    private func startLoop() {
        guard !lines.isEmpty else { return }

        Task { @MainActor in
            while true {
                // reset
                progress = 0
                shimmer = -0.8

                // 笔尖轻微抖动（更像手写）
                withAnimation(.easeInOut(duration: 0.12).repeatForever(autoreverses: true)) {
                    penJitter = 2.2
                }

                // 写字（慢速）
                withAnimation(.easeOut(duration: writeDuration)) {
                    progress = 1
                }

                // 扫光跟着写字跑一遍
                withAnimation(.linear(duration: writeDuration * 0.95)) {
                    shimmer = 1.2
                }

                // 等写完 + 停留
                try? await Task.sleep(nanoseconds: UInt64((writeDuration + holdDuration) * 1_000_000_000))

                // 停止抖动并清空
                penJitter = 0
                progress = 0

                try? await Task.sleep(nanoseconds: UInt64(restartDelay * 1_000_000_000))

                // 下一句
                index = (index + 1) % lines.count
            }
        }
    }
}
