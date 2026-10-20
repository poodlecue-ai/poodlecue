import AVFoundation

struct AudioRouteDescription: Equatable {
    let input: String
    let output: String

    static let unavailable = AudioRouteDescription(
        input: "No active input",
        output: "No active output"
    )
}

enum AudioInputPreference: String, CaseIterable, Identifiable {
    case earbuds = "Earbuds mic"
    case iPhone = "Phone mic"

    var id: Self { self }
}

final class AudioSessionManager {
    private let session = AVAudioSession.sharedInstance()

    func activate(inputPreference: AudioInputPreference) throws -> AudioRouteDescription {
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.allowBluetoothHFP, .allowBluetoothA2DP]
        )
        try session.setPreferredSampleRate(48_000)
        try session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let preferredPortType: AVAudioSession.Port = inputPreference == .iPhone
            ? .builtInMic
            : .bluetoothHFP
        if let preferredInput = session.availableInputs?.first(where: {
            $0.portType == preferredPortType
        }) {
            try session.setPreferredInput(preferredInput)
        }

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

