import CoreHaptics

/// Haptics that follow a soft squishy: one continuous buzz whose strength
/// tracks how far the toy is squeezed, and light taps for crackles and landings.
@MainActor
final class SquishHaptics {
    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?
    private var startedAt = Date.distantPast
    private var sharpness: Float = 0
    private var lastTap = Date.distantPast
    private let supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    /// After a failed start, wait a second before trying again.
    private var retryAfter = Date.distantPast

    private func ready() -> CHHapticEngine? {
        guard supported, Date() >= retryAfter else { return nil }
        if engine == nil {
            guard let made = try? CHHapticEngine() else {
                retryAfter = Date().addingTimeInterval(1)
                return nil
            }
            made.playsHapticsOnly = true
            made.isAutoShutdownEnabled = true
            made.resetHandler = { [weak self] in
                Task { @MainActor in self?.player = nil }
            }
            made.stoppedHandler = { [weak self] _ in
                Task { @MainActor in self?.player = nil }
            }
            engine = made
        }
        guard let engine, (try? engine.start()) != nil else {
            retryAfter = Date().addingTimeInterval(1)
            return nil
        }
        return engine
    }

    /// Once a frame while a finger is on the toy. `intensity` 0...1.
    func hold(intensity: Double, sharpness: Double) {
        let wanted = Float(sharpness)
        // A continuous event lasts 30 s at most, so a long hold starts a fresh one.
        if player == nil || wanted != self.sharpness || Date().timeIntervalSince(startedAt) > 25 {
            letGo()
            guard let engine = ready() else { return }
            let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: wanted),
            ], relativeTime: 0, duration: 30)
            guard let pattern = try? CHHapticPattern(events: [event], parameters: []),
                  let made = try? engine.makeAdvancedPlayer(with: pattern) else { return }
            try? made.sendParameters([CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: 0, relativeTime: 0)],
                                     atTime: CHHapticTimeImmediate)
            guard (try? made.start(atTime: CHHapticTimeImmediate)) != nil else { return }
            player = made
            self.sharpness = wanted
            startedAt = Date()
        }
        try? player?.sendParameters([CHHapticDynamicParameter(parameterID: .hapticIntensityControl,
                                                              value: Float(max(0, min(1, intensity))), relativeTime: 0)],
                                    atTime: CHHapticTimeImmediate)
    }

    /// Nothing is felt while the toy rises on its own.
    func letGo() {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
    }

    /// One light tap. `atMostPerSecond` thins out fast runs such as foam crackle.
    func tap(intensity: Double, sharpness: Double, atMostPerSecond: Double = 0) {
        let now = Date()
        if atMostPerSecond > 0, now.timeIntervalSince(lastTap) < 1 / atMostPerSecond { return }
        guard intensity > 0.01, let engine = ready() else { return }
        lastTap = now
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(max(0, min(1, intensity)))),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(sharpness)),
        ], relativeTime: 0)
        guard let pattern = try? CHHapticPattern(events: [event], parameters: []),
              let once = try? engine.makePlayer(with: pattern) else { return }
        try? once.start(atTime: CHHapticTimeImmediate)
    }
}
