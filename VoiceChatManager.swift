import Foundation
import Speech
import AVFoundation

@MainActor
class VoiceChatManager: NSObject, ObservableObject {

    enum Phase { case idle, listening, thinking, speaking }

    @Published var phase: Phase = .idle
    @Published var userText = ""
    @Published var aiText = ""

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    private let engine = AVAudioEngine()
    private let synth = AVSpeechSynthesizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?

    var sendMessage: ((String) async -> String)?

    override init() {
        super.init()
        synth.delegate = self
    }

    func start() {
        Task {
            let speechOK = await requestSpeechAuth()
            let micOK = await requestMicAuth()
            guard speechOK && micOK else { return }
            startListening()
        }
    }

    func stop() {
        silenceTimer?.invalidate()
        stopEngine()
        synth.stopSpeaking(at: .immediate)
        phase = .idle
    }

    private func requestSpeechAuth() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicAuth() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }

    func startListening() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            request = SFSpeechAudioBufferRecognitionRequest()
            guard let request else { return }
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = true

            task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    Task { @MainActor in
                        self.userText = result.bestTranscription.formattedString
                        self.scheduleSilenceTimer()
                    }
                }
                if error != nil {
                    Task { @MainActor in self.startListening() }
                }
            }

            let format = engine.inputNode.outputFormat(forBus: 0)
            engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buf, _ in
                self?.request?.append(buf)
            }

            engine.prepare()
            try engine.start()
            phase = .listening

        } catch {
            print("Audio start error: \(error)")
        }
    }

    private func scheduleSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            guard let self, !self.userText.isEmpty else { return }
            Task { await self.processText() }
        }
    }

    private func stopEngine() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }

    private func processText() async {
        let text = userText
        userText = ""
        stopEngine()
        phase = .thinking

        guard let sendMessage, !text.isEmpty else {
            startListening()
            return
        }

        let response = await sendMessage(text)
        aiText = response
        speak(response)
    }

    private func speak(_ text: String) {
        phase = .speaking
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            print("Playback session error: \(error)")
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        utterance.rate = 0.48
        utterance.pitchMultiplier = 1.1
        synth.speak(utterance)
    }
}

extension VoiceChatManager: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.startListening()
        }
    }
}
