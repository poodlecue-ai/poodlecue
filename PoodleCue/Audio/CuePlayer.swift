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

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var isGraphConfigured = false
    private var cueBuffer: AVAudioPCMBuffer?
    private var cueDurationNanoseconds: UInt64 = 0

    var onMeasurement: MeasurementHandler?

    func prepare() throws {
        guard !engine.isRunning else { return }

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
        engine.prepare()
        try engine.start()

        // Start the node once so later cue scheduling avoids cold-start work.
        player.play()
    }

    func playCachedCue() {
        guard let cueBuffer else { return }

        let requestedAt = DispatchTime.now().uptimeNanoseconds
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
            guard let self else { return }

            let renderedAt = DispatchTime.now().uptimeNanoseconds
            let estimatedStart = renderedAt > self.cueDurationNanoseconds
                ? renderedAt - self.cueDurationNanoseconds
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
        player.stop()
        engine.stop()
        engine.reset()
        cueBuffer = nil
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

