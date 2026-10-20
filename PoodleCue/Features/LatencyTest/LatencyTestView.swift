import SwiftUI

struct LatencyTestView: View {
    @StateObject private var model = LatencyTestViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    sessionCard
                    speechActivityCard
                    transcriptionCard
                    speakerCard
                    conversationCueCard
                    memoryCard
                    cueButton
                    cueMetrics

                    if let errorMessage = model.errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    measurementNote
                }
                .padding()
            }
            .navigationTitle("PoodleCue")
        }
    }

    private var speakerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Who is speaking?", systemImage: "person.2.wave.2")
                    .font(.headline)
                Spacer()
                Text("You choose")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }

            Picker("Who is speaking?", selection: $model.listeningToOtherPerson) {
                Text("Them").tag(true)
                Text("Me").tag(false)
            }
            .pickerStyle(.segmented)

            Text(model.listeningToOtherPerson
                 ? "PoodleCue will treat the next speech as theirs and enable cues. This is a label—not automatic voice detection."
                 : "PoodleCue will treat the next speech as yours. Transcription continues, but cues are paused.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var memoryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("People memory", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.headline)
                Spacer()
                Text("On this iPhone")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }

            if !model.memoryStore.memories.isEmpty {
                Menu {
                    ForEach(model.memoryStore.memories) { memory in
                        Button(memory.personName) {
                            model.selectMemory(memory)
                        }
                    }
                } label: {
                    Label("Continue a conversation", systemImage: "clock.arrow.circlepath")
                }
            }

            TextField("Person’s name, e.g. Priya", text: $model.conversationPartnerName)
                .textFieldStyle(.roundedBorder)

            TextField("What should you remember?", text: $model.memoryDraft, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)

            if let selected = model.selectedMemory {
                Text("Last saved \(selected.lastMetAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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

                if model.selectedMemory != nil {
                    Button("Forget", role: .destructive) {
                        model.forgetSelectedMemory()
                    }
                }

                Button("Save") {
                    model.saveMemory()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    model.conversationPartnerName.trimmingCharacters(in: .whitespaces).isEmpty ||
                    model.memoryDraft.trimmingCharacters(in: .whitespaces).isEmpty
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var conversationCueCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Conversation cue", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                Text("Local rules")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
            }

            Text(model.latestCue?.text ?? "A short cue will appear after a complete thought.")
                .font(.title3.weight(.semibold))
                .foregroundStyle(model.latestCue == nil ? .secondary : .primary)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)

            if let cue = model.latestCue {
                Text(cue.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    metric(label: "Rule", value: cue.generationMilliseconds)
                    metric(label: "Voice start", value: model.cueSpeechStartMilliseconds)
                }
            }

            HStack {
                Toggle("Speak cues", isOn: $model.speaksCues)
                    .font(.subheadline)
                Spacer()
                Text("Cues: \(model.cueCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Replay") {
                    model.replayLatestCue()
                }
                .disabled(model.latestCue == nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .opacity(model.isSessionActive ? 1 : 0.55)
    }

    private var transcriptionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Live transcript", systemImage: "text.bubble")
                    .font(.headline)
                Spacer()
                Text("On device")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }

            Text(model.transcript.isEmpty ? "Speak to see partial text…" : model.transcript)
                .foregroundStyle(model.transcript.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                .textSelection(.enabled)

            if !model.transcriptionLocale.isEmpty {
                Text("Language model: \(model.transcriptionLocale)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                metric(label: "First text", value: model.transcriptionLatest)
                metric(label: "Median", value: model.transcriptionMedian)
                metric(label: "p95", value: model.transcriptionP95)
            }

            Text("Partial text and timing exist only for this active session.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .opacity(model.isSessionActive ? 1 : 0.55)
    }

    private var speechActivityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Live speech detection", systemImage: "waveform")
                    .font(.headline)
                Spacer()
                Text(model.isSpeechActive ? "Speaking" : "Quiet")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(model.isSpeechActive ? .green : .secondary)
            }

            ProgressView(value: model.normalizedMicrophoneLevel)
                .tint(model.isSpeechActive ? .green : .accentColor)

            HStack {
                Text("\(model.microphoneLevelDBFS, specifier: "%.1f") dBFS")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Speech events: \(model.speechDetectionLatencies.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                metric(label: "Latest", value: model.speechDetectionLatest)
                metric(label: "Median", value: model.speechDetectionMedian)
                metric(label: "p95", value: model.speechDetectionP95)
            }

            HStack {
                Text("Speak, pause briefly, then speak again. Timing includes the current input route and 10 ms analysis window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset") {
                    model.resetSpeechMeasurements()
                }
                .font(.footnote)
                .disabled(model.speechDetectionLatencies.isEmpty)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .opacity(model.isSessionActive ? 1 : 0.55)
    }

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(model.isSessionActive ? Color.green : Color.secondary)
                    .frame(width: 10, height: 10)
                Text(model.isSessionActive ? "Session active" : "Session stopped")
                    .font(.headline)
            }

            if model.isSessionActive {
                routeRow(label: "Input", value: model.route.input)
                routeRow(label: "Output", value: model.route.output)
            }

            Picker("Microphone", selection: $model.inputPreference) {
                ForEach(AudioInputPreference.allCases) { preference in
                    Text(preference.rawValue).tag(preference)
                }
            }
            .pickerStyle(.segmented)
            .disabled(model.isSessionActive || model.isStartingSession)

            Text(model.inputPreference == .iPhone
                 ? "Best accuracy for both people. Place the phone between you; cues should remain in connected earbuds."
                 : "Best for your own voice, but Bluetooth microphone compression can omit words.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(sessionButtonTitle) {
                model.toggleSession()
            }
            .buttonStyle(.borderedProminent)
            .tint(model.isSessionActive ? .red : .accentColor)
            .disabled(model.isStartingSession)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var sessionButtonTitle: String {
        if model.isStartingSession {
            return "Starting…"
        }
        return model.isSessionActive ? "Stop session" : "Start session"
    }

    private var cueButton: some View {
        Button {
            model.playCue()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "earbuds")
                    .font(.system(size: 34))
                Text("Cue me")
                    .font(.title2.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 150)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!model.isSessionActive)
        .accessibilityHint("Plays the cached latency-test cue")
    }

    private var cueMetrics: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                metric(label: "Latest", value: model.latestLatency)
                metric(label: "Median", value: model.medianLatency)
                metric(label: "p95", value: model.p95Latency)
            }

            if let latest = model.latestMeasurement {
                Text(
                    "Latest estimate: \(latest.renderStartMilliseconds, specifier: "%.1f") ms render start + \(latest.presentationMilliseconds, specifier: "%.1f") ms output presentation"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Text("Trials: \(model.measurements.count)")
                    .foregroundStyle(.secondary)

                Spacer()

                if let passes = model.passesTarget {
                    Label(
                        passes ? "Below 200 ms" : "Above 200 ms",
                        systemImage: passes ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(passes ? .green : .orange)
                }

                Button("Reset") {
                    model.resetMeasurements()
                }
                .disabled(model.measurements.isEmpty)
            }
            .font(.footnote)
        }
    }

    private var measurementNote: some View {
        Text("Audio and full transcripts are discarded. Only a memory you review and save is kept in a protected file on this iPhone. Cues use local rules; nothing contacts a backend. Speaker choice is manual in this MVP.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func routeRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
        }
    }

    private func metric(label: String, value: Double?) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.map { String(format: "%.1f ms", $0) } ?? "—")
                .font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }
}


