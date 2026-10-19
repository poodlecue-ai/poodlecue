import AVFoundation

struct AudioRouteDescription: Equatable {
    let input: String
    let output: String

    static let unavailable = AudioRouteDescription(
        input: "No active input",
        output: "No active output"
    )
}

final class AudioSessionManager {
    private let session = AVAudioSession.sharedInstance()

    func activate() throws -> AudioRouteDescription {
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.allowBluetoothHFP]
        )
        try session.setPreferredSampleRate(48_000)
        try session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        return currentRoute()
    }

    func deactivate() {
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    func currentRoute() -> AudioRouteDescription {
        let route = session.currentRoute
        let input = route.inputs.first.map { "\($0.portName) · \($0.portType.rawValue)" }
            ?? "No active input"
        let output = route.outputs.first.map { "\($0.portName) · \($0.portType.rawValue)" }
            ?? "No active output"
        return AudioRouteDescription(input: input, output: output)
    }
}

