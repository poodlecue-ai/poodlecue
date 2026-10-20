import AVFoundation

struct CueLatencyMeasurement: Identifiable, Equatable {
    let id = UUID()
    let renderStartMilliseconds: Double
    let presentationMilliseconds: Double

    var milliseconds: Double {
        renderStartMilliseconds + presentationMilliseconds
    }
}

final class CuePlayer {
    typealias MeasurementHandler = (CueLatencyMeasurement) -> Void
    typealias SpeechActivityHandler = (SpeechActivitySnapshot) -> Void

    private var engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private let speechDetector = SpeechActivityDetector()
    private var isGraphConfigured = false
    private var isInputTapInstalled = false
    private var cueBuffer: AVAudioPCMBuffer?
    private var cueDurationNanoseconds: UInt64 = 0
    private var lastLevelUpdateHostTime: UInt64 = 0
    private var sessionGeneration: UInt64 = 0

    var onMeasurement: MeasurementHandler?
    var onSpeechActivity: SpeechActivityHandler?

    func prepare() throws {
        guard !engine.isRunning else { return }
        sessionGeneration &+= 1

        let format = AVAudioFormat(
            standardFormatWithSampleRate: 48_000,
            channels: 1
        )!

        if !isGraphConfigured {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            isGraphConfigured = true
        }

        cueBuffer = makeCueBuffer(format: format)
        installInputTap()
        engine.prepare()
        try engine.start()

        // Start the node once so later cue scheduling avoids cold-start work.
        player.play()
    }

    func playCachedCue() {
        guard let cueBuffer else { return }

        let requestedAt = DispatchTime.now().uptimeNanoseconds
        let generation = sessionGeneration
        let cueDurationNanoseconds = cueDurationNanoseconds
        let session = AVAudioSession.sharedInstance()
        let graphPresentationLatency = max(
            player.outputPresentationLatency,
            engine.outputNode.presentationLatency
        )
        let routePresentationLatency = session.outputLatency + session.ioBufferDuration
        let presentationMilliseconds = max(
            graphPresentationLatency,
            routePresentationLatency
        ) * 1_000

        player.scheduleBuffer(
            cueBuffer,
            completionCallbackType: .dataRendered
        ) { [weak self] _ in
            guard
                let self,
                self.sessionGeneration == generation
            else { return }

            let renderedAt = DispatchTime.now().uptimeNanoseconds
            let estimatedStart = renderedAt > cueDurationNanoseconds
                ? renderedAt - cueDurationNanoseconds
                : renderedAt
            let elapsed = estimatedStart > requestedAt
                ? estimatedStart - requestedAt
                : 0
            let measurement = CueLatencyMeasurement(
                renderStartMilliseconds: Double(elapsed) / 1_000_000,
                presentationMilliseconds: presentationMilliseconds
            )

            DispatchQueue.main.async { [weak self] in
                self?.onMeasurement?(measurement)
            }
        }
    }

    func stop() {
        sessionGeneration &+= 1

        if isInputTapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            isInputTapInstalled = false
        }
        player.stop()
        engine.stop()
        speechDetector.reset()
        cueBuffer = nil
        cueDurationNanoseconds = 0
        lastLevelUpdateHostTime = 0

        // Voice-processing I/O can retain stale render and capture state when
        // the same engine graph is stopped and started again. Rebuild the graph
        // so every user session receives fresh I/O nodes and timelines.
        engine = AVAudioEngine()
        player = AVAudioPlayerNode()
        isGraphConfigured = false
    }

    private func installInputTap() {
        guard !isInputTapInstalled else { return }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let bufferSize = AVAudioFrameCount(max(1, format.sampleRate * 0.01))
        let bufferDuration = Double(bufferSize) / max(format.sampleRate, 1)
        let session = AVAudioSession.sharedInstance()
        let routeLatency = session.inputLatency + session.ioBufferDuration
        let modeledOnsetLatency = (
            max(input.presentationLatency, routeLatency) + bufferDuration
        ) * 1_000

        speechDetector.beginSession(
            modeledOnsetLatencyMilliseconds: modeledOnsetLatency
        )
        lastLevelUpdateHostTime = 0
        let generation = sessionGeneration

        input.installTap(
            onBus: 0,
            bufferSize: bufferSize,
            format: format
        ) { [weak self] buffer, time in
            guard
                let self,
                self.sessionGeneration == generation
            else { return }

            let snapshot = self.speechDetector.process(
                buffer: buffer,
                capturedAt: time
            )
            let now = mach_absolute_time()
            let shouldPublishLevel = AVAudioTime.seconds(
                forHostTime: now - self.lastLevelUpdateHostTime
            ) >= 0.05

            if snapshot.onsetLatencyMilliseconds != nil || shouldPublishLevel {
                self.lastLevelUpdateHostTime = now
                DispatchQueue.main.async { [weak self] in
                    self?.onSpeechActivity?(snapshot)
                }
            }
        }

        isInputTapInstalled = true
    }

    private func makeCueBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer {
        let duration = 0.12
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        )!
        buffer.frameLength = frameCount

        let frequency = 660.0
        let amplitude: Float = 0.16
        let fadeFrames = max(1, Int(format.sampleRate * 0.01))

        if let samples = buffer.floatChannelData?[0] {
            for frame in 0..<Int(frameCount) {
                let phase = 2.0 * Double.pi * frequency * Double(frame) / format.sampleRate
                let fadeIn = min(1.0, Float(frame) / Float(fadeFrames))
                let remaining = Int(frameCount) - frame
                let fadeOut = min(1.0, Float(remaining) / Float(fadeFrames))
                samples[frame] = sin(Float(phase)) * amplitude * min(fadeIn, fadeOut)
            }
        }

        cueDurationNanoseconds = UInt64(duration * 1_000_000_000)
        return buffer
    }
}

