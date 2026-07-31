import SwiftUI

struct ContentView: View {
    @StateObject private var game = GameViewModel()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(red: 0.025, green: 0.045, blue: 0.075)

                JumpSceneView(game: game)
                    .frame(width: proxy.size.width, height: proxy.size.height)

                if !game.isWelcomePresented {
                    VStack(spacing: 0) {
                        header
                        Spacer()
                        instruction
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)

            if game.isWelcomePresented {
                welcomeOverlay
            }
        }
        .ignoresSafeArea()
        .overlay {
            if game.state == .gameOver {
                gameOverOverlay
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("GLASS HOP")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                Text("\(game.score)")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            Spacer()
            Button {
                game.restart()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(GlassIconButtonStyle())
            .accessibilityLabel("重新开始")
        }
    }

    private var welcomeOverlay: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 94)

            Text("GLASS HOP")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.94))

            Text("FLOAT INTO THE NEXT MOVE")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.52))
                .padding(.top, 8)

            Spacer()

            Button {
                game.start()
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 68, height: 68)
            }
            .buttonStyle(WelcomePlayButtonStyle())
            .accessibilityLabel("开始游戏")

            Spacer()
                .frame(height: 92)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.28))
        .transition(.opacity)
    }

    @ViewBuilder
    private var instruction: some View {
        if game.state == .ready || game.state == .charging {
            LiquidGlassSurface {
                Group {
                    if game.state == .ready {
                        Text("按住屏幕蓄力，松开起跳")
                    } else {
                        Text("蓄力 \(Int(game.charge * 100))%")
                            .monospacedDigit()
                    }
                }
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .frame(minWidth: 176, minHeight: 42)
                .padding(.horizontal, 16)
            }
            .animation(.easeInOut(duration: 0.15), value: game.state)
        }
    }

    private var gameOverOverlay: some View {
        ZStack {
            Color.black.opacity(0.30).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white)
                Text("本次得分")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
                Text("\(game.score)")
                    .font(.system(size: 58, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .padding(.bottom, 4)
                Button {
                    game.restart()
                } label: {
                    Label("再来一次", systemImage: "arrow.clockwise")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(GlassPrimaryButtonStyle())
            }
            .foregroundStyle(.white)
            .frame(width: 272)
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.22), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.34), radius: 28, y: 14)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.94)))
    }
}

private struct LiquidGlassSurface<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect()
        } else {
            fallback
        }
#else
        fallback
#endif
    }

    private var fallback: some View {
        content
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.7))
    }
}

private struct GlassIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        LiquidGlassSurface {
            configuration.label
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
        }
        .scaleEffect(configuration.isPressed ? 0.92 : 1)
        .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct GlassPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        LiquidGlassSurface {
            configuration.label
                .foregroundStyle(.white)
        }
        .scaleEffect(configuration.isPressed ? 0.97 : 1)
        .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct WelcomePlayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Circle()
            .fill(.ultraThinMaterial)
            .overlay(Circle().strokeBorder(.white.opacity(0.42), lineWidth: 0.8))
            .overlay(configuration.label)
            .frame(width: 68, height: 68)
            .shadow(color: .black.opacity(0.30), radius: 18, y: 8)
            .scaleEffect(configuration.isPressed ? 0.90 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

@MainActor
final class GameViewModel: ObservableObject {
    @Published private(set) var score = 0
    @Published private(set) var charge: CGFloat = 0
    @Published private(set) var state: GameState = .ready
    @Published private(set) var isWelcomePresented = true
    let engine = JumpGameEngine()

    init() {
        engine.gameStateChanged = { [weak self] state, score, charge in
            self?.state = state
            self?.score = score
            self?.charge = charge
        }
    }

    func attach(to view: JumpSCNView) {
        engine.attach(to: view)
    }

    func restart() {
        engine.restart()
    }

    func start() {
        isWelcomePresented = false
        engine.restart(playsFeedback: false)
    }
}

enum GameState: Equatable {
    case ready
    case charging
    case jumping
    case gameOver
}
