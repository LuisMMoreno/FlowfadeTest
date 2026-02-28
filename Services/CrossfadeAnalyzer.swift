import Foundation
import AVFoundation

/// Analyzes the tail end of audio files to determine adaptive crossfade timing.
/// Uses RMS energy measurement — no BPM or spectral analysis.
struct CrossfadeAnalyzer {

    /// Analyze the tail of an audio file and return the recommended crossfade multiplier.
    /// The multiplier adjusts the user's configured crossfade duration:
    /// - 1.0 = full crossfade (song ends abruptly)
    /// - ~0.5 = shortened crossfade (song fades out naturally)
    static func analyzeTail(of url: URL, baseDuration: TimeInterval) async -> Double {
        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            let sampleRate = format.sampleRate
            let totalFrames = AVAudioFrameCount(file.length)

            // Calculate how many frames to read from the tail
            let analysisFrames = AVAudioFrameCount(sampleRate * Constants.crossfadeAnalysisWindow)
            let framesToRead = min(analysisFrames, totalFrames)

            // Seek to the tail position
            let startFrame = AVAudioFramePosition(totalFrames - framesToRead)
            file.framePosition = startFrame

            // Read the tail audio data
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: framesToRead
            ) else {
                return 1.0
            }

            try file.read(into: buffer, frameCount: framesToRead)

            // Extract samples from the first channel
            guard let channelData = buffer.floatChannelData else {
                return 1.0
            }

            let samples = Array(UnsafeBufferPointer(
                start: channelData[0],
                count: Int(buffer.frameLength)
            ))

            // Calculate RMS in windows
            let rmsValues = AudioMath.rmsWindows(
                samples: samples,
                sampleRate: sampleRate,
                windowDuration: Constants.rmsWindowSize
            )

            // Determine adaptive multiplier
            return AudioMath.adaptiveCrossfadeMultiplier(tailRMSValues: rmsValues)

        } catch {
            print("CrossfadeAnalyzer error: \(error)")
            return 1.0 // Default to full crossfade on error
        }
    }
}
