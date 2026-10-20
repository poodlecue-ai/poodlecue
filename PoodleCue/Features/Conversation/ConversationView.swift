import SwiftUI

struct ConversationView: View {
    @ObservedObject var model: LatencyTestViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    personCard
                    sessionCard

                    if model.isSessionActive {
                        speakerCard
                    }

                    if model.isAIShadowConfigured {
                        aiShadowCard
                        aiEvaluationCard
                    } else {
                        cueCard
                    }

                    if model.isSessionActive || !model.transcript.isEmpty {
                        transcriptCard
                    }

                    if !model.transcript.isEmpty || model.selectedMemory != nil {
                        memoryCard
                    }

                    if let errorMessage = model.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    privacyNote
                }
                .padding()
            }
            .navigationTitle("PoodleCue")
        }
    }

    private var personCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Who are you meeting?", systemImage: "person.crop.circle")
                .font(.headline)

            if !model.memoryStore.memories.isEmpty {
                Menu {
                    ForEach(model.memoryStore.memories) { memory in
                        Button(memory.personName) {
                            model.selectMemory(memory)
                        }
                    }
                    Divider()
                    Button("Someone new") {
                        model.beginNewConversation()
                    }
                } label: {
                    HStack {
                        Text(model.selectedMemory?.personName ?? "Choose a saved person")
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(model.isSessionActive)
            }

            if model.selectedMemory == nil {
                TextField("Name, e.g. Priya", text: $model.conversationPartnerName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.isSessionActive)
            } else if let memory = model.selectedMemory {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Last time")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(memory.summary)
                    Text(memory.lastMetAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .cardStyle()
    }

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(model.isSessionActive ? Color.green : Color.secondary)
                    .frame(width: 10, height: 10)
                Text(model.isSessionActive ? "Listening" : "Ready")
                    .font(.headline)
                Spacer()
                if model.isSessionActive {
                    Text(model.isSpeechActive ? "Speech" : "Quiet")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(model.isSpeechActive ? .green : .secondary)
                }
            }

            if model.isSessionActive {
                ProgressView(value: model.normalizedMicrophoneLevel)
                    .tint(model.isSpeechActive ? .green : .blue)
                Label(model.route.input, systemImage: "mic.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(model.route.output, systemImage: "earbuds")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Microphone", selection: $model.inputPreference) {
                    ForEach(AudioInputPreference.allCases) { preference in
                        Text(preference.rawValue).tag(preference)
                    }
                }
                .pickerStyle(.segmented)

                Text(model.inputPreference == .iPhone
                     ? "Recommended: place the phone between both people. Cues remain private in your earbuds."
                     : "Bluetooth compression may miss words at a natural speaking pace.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                model.toggleSession()
            } label: {
                Text(sessionButtonTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(model.isSessionActive ? .red : .blue)
            .disabled(model.isStartingSession)
        }
        .cardStyle()
    }

    private var speakerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Who is speaking now?")
                .font(.headline)
            Picker("Speaker", selection: $model.listeningToOtherPerson) {
                Text("Them — cues on").tag(true)
                Text("Me — cues paused").tag(false)
            }
            .pickerStyle(.segmented)
            Text("Manual for now; PoodleCue is not identifying voices automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private var cueCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Your cue", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                Toggle("Speak", isOn: $model.speaksCues)
                    .labelsHidden()
            }

            Text(model.latestCue?.text ?? cuePlaceholder)
                .font(.title3.weight(.semibold))
                .foregroundStyle(model.latestCue == nil ? .secondary : .primary)
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)

            if let cue = model.latestCue {
                HStack {
                    Text(cue.intent.rawValue)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                    Text(cue.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Hear again") {
                        model.replayLatestCue()
                    }
                    .font(.footnote)
                }

                Divider()

                HStack(spacing: 10) {
                    Text(model.latestCueFeedback.map { "Recorded: \($0.rawValue)" } ?? "Was this useful?")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        model.recordCueFeedback(.useful)
                    } label: {
                        Image(systemName: "hand.thumbsup")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        model.recordCueFeedback(.notUseful)
                    } label: {
                        Image(systemName: "hand.thumbsdown")
                    }
                    .buttonStyle(.bordered)

                    Menu {
                        Button("Too late") {
                            model.recordCueFeedback(.tooLate)
                        }
                        Button("Repeated") {
                            model.recordCueFeedback(.repeated)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .cardStyle(color: .blue)
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Live transcript", systemImage: "text.bubble")
                    .font(.headline)
                Spacer()
                Text("Not saved")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
            Text(model.transcript.isEmpty ? "Listening…" : model.transcript)
                .foregroundStyle(model.transcript.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
        }
        .cardStyle()
    }

    private var aiShadowCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Your AI cue", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                Toggle("Speak", isOn: $model.speaksCues)
                    .labelsHidden()
                Text("AI only · \(model.aiTransportLabel)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            switch model.aiShadowState {
            case .unavailable, .idle:
                Text("Listening for their next complete thought…")
                    .foregroundStyle(.secondary)
            case .comparing:
                HStack {
                    ProgressView()
                    Text("Generating an AI cue…")
                        .foregroundStyle(.secondary)
                }
            case let .failed(message):
                Text("\(message) No local fallback cue was played.")
                    .foregroundStyle(.secondary)
            case let .ready(result):
                if result.shouldSpeak {
                    Text(result.cue)
                        .font(.title3.weight(.semibold))
                    Text(result.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text("AI \(Int(result.latencyMilliseconds)) ms")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let endToEar = model.latestEndToEarMilliseconds {
                            Text("End-to-ear \(Int(endToEar)) ms")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                        } else if model.speaksCues {
                            Text("Measuring end-to-ear…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Hear AI") {
                            model.replayLatestAICue()
                        }
                        .font(.footnote)
                    }
                } else {
                    Text("Stay silent")
                        .font(.title3.weight(.semibold))
                    Text("The AI judged that another cue would not add value · \(Int(result.latencyMilliseconds)) ms")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .cardStyle(color: .purple)
    }

    private var aiEvaluationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("AI performance", systemImage: "chart.bar.fill")
                    .font(.headline)
                Spacer()
                Text("\(model.aiRealtimeRequestCount) realtime turns")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                evaluationMetric(
                    label: "AI median",
                    value: formattedEvaluationLatency(model.aiRealtimeMedianLatency)
                )
                evaluationMetric(
                    label: "Ear median",
                    value: formattedEvaluationLatency(model.endToEarMedianLatency)
                )
                evaluationMetric(
                    label: "Ear p95",
                    value: formattedEvaluationLatency(model.endToEarP95Latency)
                )
            }

            Text("End-to-ear measures from the estimated end of their speech until the cue actually begins. Fallback / failed: \(model.aiRealtimeFallbackCount) / \(model.aiRealtimeFailureCount).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle(color: .purple)
    }

    private func evaluationMetric(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .padding(.horizontal, 4)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func formattedEvaluationLatency(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value)) ms"
    }

    private var memoryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Remember for next time", systemImage: "lock.shield")
                .font(.headline)

            if model.conversationPartnerName.isEmpty {
                TextField("Person’s name", text: $model.conversationPartnerName)
                    .textFieldStyle(.roundedBorder)
            }

            TextField("Short note you approve", text: $model.memoryDraft, axis: .vertical)
                .lineLimit(3...5)
                .textFieldStyle(.roundedBorder)

            if let message = model.memoryStatusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Draft from transcript") {
                    model.prepareMemoryDraft()
                }
                .disabled(model.transcript.isEmpty)
                Spacer()
                Button("Save memory") {
                    model.saveMemory()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    model.conversationPartnerName.trimmingCharacters(in: .whitespaces).isEmpty ||
                    model.memoryDraft.trimmingCharacters(in: .whitespaces).isEmpty
                )
            }
        }
        .cardStyle()
    }

    private var privacyNote: some View {
        Label(
            model.isAIShadowConfigured
                ? "Audio and full transcripts are discarded. AI-only mode sends only the latest text turn and optional reviewed memory. Only aggregate latency, silence, and failure counts are saved on this iPhone."
                : "Audio and full transcripts are discarded. Only a note you review and save remains on this iPhone.",
            systemImage: "hand.raised.fill"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sessionButtonTitle: String {
        if model.isStartingSession { return "Starting…" }
        return model.isSessionActive ? "End conversation" : "Start conversation"
    }

    private var cuePlaceholder: String {
        if model.isSessionActive && model.listeningToOtherPerson {
            return "Listening for their next complete thought…"
        }
        if model.isSessionActive {
            return "Cues are paused while you speak."
        }
        return "Choose someone or start listening for a cue."
    }
}

private extension View {
    func cardStyle(color: Color = .secondary) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
    }
}
