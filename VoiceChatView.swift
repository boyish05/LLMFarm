import SwiftUI

struct VoiceChatView: View {
    @EnvironmentObject var aiChatModel: AIChatModel
    @StateObject private var voice = VoiceChatManager()
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(phaseColor.opacity(0.2))
                        .frame(width: 160, height: 160)
                        .scaleEffect(voice.phase == .listening ? 1.3 : 1.0)
                        .animation(
                            voice.phase == .listening
                                ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                                : .default,
                            value: voice.phase
                        )

                    Circle()
                        .fill(phaseColor)
                        .frame(width: 100, height: 100)

                    Image(systemName: phaseIcon)
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                }

                Text(phaseLabel)
                    .font(.title2.bold())
                    .foregroundColor(.white)

                VStack(spacing: 12) {
                    if !voice.userText.isEmpty {
                        Text("あなた: \(voice.userText)")
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    if !voice.aiText.isEmpty {
                        Text(voice.aiText)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }

                Spacer()

                Button {
                    voice.stop()
                    dismiss()
                } label: {
                    Text("終了")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(width: 120, height: 48)
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(24)
                }
                .padding(.bottom, 48)
            }
        }
        .onAppear {
            voice.sendMessage = { [weak aiChatModel] text in
                guard let model = aiChatModel else { return "" }
                await model.Send(message: text)
                while model.predicting {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                return model.messages.last?.text ?? ""
            }
            voice.start()
        }
        .onDisappear { voice.stop() }
    }

    var phaseColor: Color {
        switch voice.phase {
        case .idle: return .gray
        case .listening: return .green
        case .thinking: return .yellow
        case .speaking: return .blue
        }
    }

    var phaseIcon: String {
        switch voice.phase {
        case .idle: return "mic.slash"
        case .listening: return "mic.fill"
        case .thinking: return "brain"
        case .speaking: return "speaker.wave.2.fill"
        }
    }

    var phaseLabel: String {
        switch voice.phase {
        case .idle: return "待機中"
        case .listening: return "聞いています..."
        case .thinking: return "考えています..."
        case .speaking: return "話しています..."
        }
    }
}
