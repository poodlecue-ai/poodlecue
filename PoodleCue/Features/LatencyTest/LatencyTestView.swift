import SwiftUI

struct LatencyTestView: View {
    @StateObject private var model = LatencyTestViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    sessionCard
                    cueButton
                    metrics

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

    private var metrics: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                metric(label: "Latest", value: model.latestLatency)
                metric(label: "Median", value: model.medianLatency)
                metric(label: "p95", value: model.p95Latency)
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
        Text("This prototype measures estimated software render-start latency. Physical AirPods latency requires an external acoustic test.")
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


