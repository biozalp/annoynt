// Maps a desired slide duration to the release velocity of the synthetic
// swipe. The Dock then plays its *own* space animation, just shorter — the
// same spring it uses after a fast trackpad flick.
//
// The table was measured on macOS 27.0.1 (26A434), MacBook built-in display at
// 120 Hz, by screen-recording each switch at 120 fps (see JOURNAL 2026-10-02).
// Velocities up to ~45 all give the full-length native animation (~750–900 ms);
// from 50 upward it shortens very steeply, and above ~100 it's instant.

import Foundation

enum SpeedCurve {
    /// (visible slide duration in seconds, release velocity), longest first.
    private static let samples: [(duration: Double, velocity: Double)] = [
        (0.480, 50.0),
        (0.380, 51.0),
        (0.273, 51.5),
        (0.200, 52.0),
        (0.133, 52.5),
        (0.118, 53.0),
        (0.088, 54.0),
        (0.063, 57.0),
        (0.053, 60.0),
        (0.036, 65.0),
        (0.013, 80.0),
    ]

    static let longest = samples.first!.duration
    static let shortest = samples.last!.duration
    static let instantVelocity = DockSwipe.commitVelocity

    /// Release velocity for `duration` seconds; anything under the shortest
    /// measured slide is instant.
    static func velocity(for duration: TimeInterval) -> Double {
        if duration < shortest { return instantVelocity }
        if duration >= longest { return samples.first!.velocity }
        // Interpolate in log-duration: the curve is roughly exponential.
        for (a, b) in zip(samples, samples.dropFirst()) where duration <= a.duration && duration >= b.duration {
            let t = (log(a.duration) - log(duration)) / (log(a.duration) - log(b.duration))
            return a.velocity + (b.velocity - a.velocity) * t
        }
        return instantVelocity
    }
}
