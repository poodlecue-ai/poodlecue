import AVFoundation

struct SpeechActivitySnapshot: Equatable {
    let levelDBFS: Double
    let isSpeechActive: Bool
    let onsetLatencyMilliseconds: Double?
}

final class SpeechActivityDetector {
    private let speechThresholdDBFS: Double
    private let releaseDuration: Double

    private var isSpeechActive = false
    private var quietDuration = 0.0

    init(
        speechThresholdDBFS: Double = -38,
        releaseDuration: Double = 0.35
    ) {
        self.speechThresholdDBFS = speechThresholdDBFS
        self.releaseDuration = releaseDuration
    }

    func process(
        buffer: AVAudioPCMBuffer,
        capturedAt time: AVAudioTime
    ) -> SpeechActivitySnapshot {
        let levelDBFS = calculateLevelDBFS(buffer)
        let duration = Double(buffer.frameLength) / max(buffer.format.sampleRate, 1)
        var onsetLatencyMilliseconds: Double?

        if levelDBFS >= speechThresholdDBFS {
            quietDuration = 0

            if !isSpeechActive {
                isSpeechActive = true
                onsetLatencyMilliseconds = bufferAgeMilliseconds(capturedAt: time)
            }
        } else if isSpeechActive {
            quietDuration += duration
            if quietDuration >= releaseDuration {
                isSpeechActive = false
                quietDuration = 0
            }
        }

        return SpeechActivitySnapshot(
            levelDBFS: levelDBFS,
            isSpeechActive: isSpeechActive,
            onsetLatencyMilliseconds: onsetLatencyMilliseconds
        )
    }

    func reset() {
        isSpeechActive = false
        quietDuration = 0
    }

    private func calculateLevelDBFS(_ buffer: AVAudioPCMBuffer) -> Double {
        guard
            let channelData = buffer.floatChannelData,
            buffer.frameLength > 0
        else {
            return -80
        }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        var sumOfSquares = 0.0

        for channel in 0..<channelCount {
            let samples = channelData[channel]
            for frame in 0..<frameLength {
                let sample = Double(samples[frame])
                sumOfSquares += sample * sample
            }
        }

        let sampleCount = max(frameLength * channelCount, 1)
        let rms = sqrt(sumOfSquares / Double(sampleCount))
        return max(-80, 20 * log10(max(rms, 0.000_1)))
    }

    private func bufferAgeMilliseconds(capturedAt time: AVAudioTime) -> Double? {
        guard time.isHostTimeValid else { return nil }

        let now = AVAudioTime.seconds(forHostTime: mach_absolute_time())
        let captured = AVAudioTime.seconds(forHostTime: time.hostTime)
        return max(0, (now - captured) * 1_000)
    }
}
