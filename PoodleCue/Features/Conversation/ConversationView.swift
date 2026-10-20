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

                    cueCard

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
                    Text(cue.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Hear again") {
                        model.replayLatestCue()
                    }
                    .font(.footnote)
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
            "Audio and full transcripts are discarded. Only a note you review and save remains on this iPhone.",
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
