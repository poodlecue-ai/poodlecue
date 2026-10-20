import SwiftUI

struct LatencyTestView: View {
    @StateObject private var model = LatencyTestViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    sessionCard
                    speechActivityCard
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

            Button(model.isSessionActive ? "Stop session" : "Start session") {
                model.toggleSession()
            }
            .buttonStyle(.borderedProminent)
            .tint(model.isSessionActive ? .red : .accentColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
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
        Text("Microphone samples are analyzed live and discarded—this build does not save or transmit audio. Detection timing uses the buffer clock when valid and the current route latency after a clock discontinuity. Final acoustic validation still requires an external test.")
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


