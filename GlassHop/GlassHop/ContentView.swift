import SwiftUI

struct ContentView: View {
    @StateObject private var game = GameViewModel()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(red: 0.025, green: 0.045, blue: 0.075)

                JumpSceneView(game: game)
                    .frame(width: proxy.size.width, height: proxy.size.height)

                VStack(spacing: 0) {
                    header
                    Spacer()
                    instruction
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
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

    private var instruction: some View {
        LiquidGlassSurface {
            Group {
                if game.state == .ready {
                    Text("按住屏幕蓄力，松开起跳")
                } else if game.state == .charging {
                    Text("蓄力 \(Int(game.charge * 100))%")
                        .monospacedDigit()
                } else {
                    Text(" ")
                }
            }
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.92))
            .frame(minWidth: 176, minHeight: 42)
            .padding(.horizontal, 16)
        }
        .animation(.easeInOut(duration: 0.15), value: game.state)
    }

    private var gameOverOverlay: some View {
        ZStack {
            Color.black.opacity(0.22).ignoresSafeArea()
            LiquidGlassSurface {
                VStack(spacing: 16) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.white)
                    Text("本次得分")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.68))
                    Text("\(game.score)")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Button {
                        game.restart()
                    } label: {
                        Label("再来一次", systemImage: "arrow.clockwise")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(GlassPrimaryButtonStyle())
                }
                .foregroundStyle(.white)
                .frame(width: 260)
                .padding(26)
            }
            .shadow(color: .black.opacity(0.30), radius: 24, y: 12)
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

@MainActor
final class GameViewModel: ObservableObject {
    @Published private(set) var score = 0
    @Published private(set) var charge: CGFloat = 0
    @Published private(set) var state: GameState = .ready
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
}

enum GameState: Equatable {
    case ready
    case charging
    case jumping
    case gameOver
}
