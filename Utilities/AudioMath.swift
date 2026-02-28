import Foundation
import Accelerate

struct AudioMath {
    // MARK: - Equal-Power Crossfade Curves

    /// Equal-power fade-out curve: cos(t * π/2)
    /// Input t: 0.0 (full volume) → 1.0 (silence)
    /// Output: 1.0 → 0.0 following cosine curve
    static func fadeOutVolume(progress t: Float) -> Float {
        let clamped = max(0, min(1, t))
        return cos(clamped * .pi / 2)
    }

    /// Equal-power fade-in curve: sin(t * π/2)
    /// Input t: 0.0 (silence) → 1.0 (full volume)
    /// Output: 0.0 → 1.0 following sine curve
    static func fadeInVolume(progress t: Float) -> Float {
        let clamped = max(0, min(1, t))
        return sin(clamped * .pi / 2)
    }

    // MARK: - RMS Energy Calculation

    /// Calculate RMS (Root Mean Square) energy of an audio buffer.
    /// Uses Accelerate framework for SIMD-optimized computation.
    static func rmsEnergy(of samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }

        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        return rms
    }

    /// Calculate RMS energy in windows across a buffer.
    /// Returns an array of RMS values, one per window.
    static func rmsWindows(
        samples: [Float],
        sampleRate: Double,
        windowDuration: TimeInterval = Constants.rmsWindowSize
    ) -> [Float] {
        let windowSize = Int(sampleRate * windowDuration)
        guard windowSize > 0 else { return [] }

        var results: [Float] = []
        var offset = 0

        while offset + windowSize <= samples.count {
            let window = Array(samples[offset..<(offset + windowSize)])
            results.append(rmsEnergy(of: window))
            offset += windowSize
        }

        // Handle remaining samples
        if offset < samples.count {
            let remaining = Array(samples[offset...])
            results.append(rmsEnergy(of: remaining))
        }

        return results
    }

    /// Determine adaptive crossfade multiplier based on the tail energy of a song.
    /// Returns a value between minCrossfadeMultiplier and 1.0
    ///
    /// - If the song fades out naturally (low RMS at end): shorter crossfade
    /// - If the song ends abruptly (high RMS at end): full crossfade
    static func adaptiveCrossfadeMultiplier(tailRMSValues: [Float]) -> Double {
        guard !tailRMSValues.isEmpty else { return 1.0 }

        // Check the last few windows
        let checkCount = min(3, tailRMSValues.count)
        let lastWindows = Array(tailRMSValues.suffix(checkCount))
        let averageRMS = lastWindows.reduce(0, +) / Float(lastWindows.count)

        if averageRMS < Constants.naturalFadeThreshold {
            // Song fades out naturally — use shorter crossfade
            return Constants.minCrossfadeMultiplier
        }

        // Check if there's a declining trend
        if tailRMSValues.count >= 3 {
            let firstHalf = Array(tailRMSValues.prefix(tailRMSValues.count / 2))
            let secondHalf = Array(tailRMSValues.suffix(tailRMSValues.count / 2))
            let firstAvg = firstHalf.reduce(0, +) / Float(firstHalf.count)
            let secondAvg = secondHalf.reduce(0, +) / Float(secondHalf.count)

            if secondAvg < firstAvg * 0.5 {
                // Significant decline — moderate crossfade
                return 0.7
            }
        }

        // Song ends with energy — use full crossfade
        return 1.0
    }

    // MARK: - Utility

    /// Convert decibels to linear volume
    static func dbToLinear(_ db: Float) -> Float {
        return powf(10, db / 20)
    }

    /// Convert linear volume to decibels
    static func linearToDb(_ linear: Float) -> Float {
        guard linear > 0 else { return -.infinity }
        return 20 * log10f(linear)
    }
}
