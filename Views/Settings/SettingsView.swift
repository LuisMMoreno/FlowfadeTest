import SwiftUI

/// Settings view for crossfade duration, toggles, and app info.
struct SettingsView: View {

    @EnvironmentObject var audioEngine: AudioEngine

    var body: some View {
        NavigationStack {
            Form {
                // Crossfade Section
                Section {
                    Toggle("Crossfade Enabled", isOn: $audioEngine.isCrossfadeEnabled)

                    if audioEngine.isCrossfadeEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Duration")
                                Spacer()
                                Text("\(String(format: "%.1f", audioEngine.crossfadeDuration))s")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }

                            Slider(
                                value: $audioEngine.crossfadeDuration,
                                in: Constants.minCrossfadeDuration...Constants.maxCrossfadeDuration,
                                step: 0.5
                            )

                            HStack {
                                Text("\(Int(Constants.minCrossfadeDuration))s")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Spacer()
                                Text("\(Int(Constants.maxCrossfadeDuration))s")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Label("Adaptive Crossfade", systemImage: "waveform.path")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text("Automatically adjusts crossfade timing based on how each song ends. Songs that fade out naturally get shorter crossfades.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Crossfade")
                } footer: {
                    Text("Crossfade blends the end of one song smoothly into the beginning of the next, eliminating silence between tracks.")
                }

                // Audio Section
                Section {
                    LabeledContent("Supported Formats") {
                        Text("MP3, M4A, WAV, FLAC, AAC, AIFF")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Audio")
                }

                // About Section
                Section {
                    LabeledContent("Version", value: "1.0.0")
                    LabeledContent("Platform", value: "iOS")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("About Flowfade")
                            .fontWeight(.medium)

                        Text("A local music player designed for one thing: making your music sound continuous and beautiful. No internet, no accounts, no streaming — just your music, playing seamlessly.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("About")
                }

                // Storage Section
                Section {
                    Button(role: .destructive) {
                        // This would clear the cache, not implemented here
                    } label: {
                        Label("Clear Audio Cache", systemImage: "trash")
                    }
                    .disabled(true) // Placeholder for future
                } header: {
                    Text("Storage")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AudioEngine.shared)
}
