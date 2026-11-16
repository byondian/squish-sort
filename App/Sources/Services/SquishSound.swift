import AVFoundation
import SquishSoft

/// The quiet, close sounds of a squishy being squeezed. Loops run silently and
/// only their volume moves; grains are short files fired as the squish asks for
/// them. What to play each frame is decided by `SquishSoundMixer`; this only plays it.
@MainActor
final class SquishSound {
    private struct Index: Decodable {
        var loops: [String: String]
        var grains: [String: [String]]
        var oneShots: [String: String]
    }

    private let engine = AVAudioEngine()
    private var loops: [String: (player: AVAudioPlayerNode, buffer: AVAudioPCMBuffer, volume: Float)] = [:]
    private var grains: [String: [AVAudioPCMBuffer]] = [:]
    private var oneShots: [String: AVAudioPCMBuffer] = [:]
    private var voices: [AVAudioPlayerNode] = []
    private var nextVoice = 0
    private var loaded = false
    private var failed = false

    private func read(_ file: String) -> AVAudioPCMBuffer? {
        let name = (file as NSString).deletingPathExtension
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let audio = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: AVAudioFrameCount(audio.length)),
              (try? audio.read(into: buffer)) != nil else { return nil }
        return buffer
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let url = Bundle.main.url(forResource: "asmr", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let index = try? JSONDecoder().decode(Index.self, from: data) else {
            failed = true
            return
        }
        var format: AVAudioFormat?
        for (name, file) in index.loops {
            guard let buffer = read(file) else { continue }
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
            player.volume = 0
            loops[name] = (player, buffer, 0)
            format = format ?? buffer.format
        }
        for (name, files) in index.grains { grains[name] = files.compactMap { read($0) } }
        for (name, file) in index.oneShots { oneShots[name] = read(file) }
        guard let format else {
            failed = true
            return
        }
        // Every file is mono at the same rate, so one set of voices plays them all.
        for _ in 0..<SquishTuning.standard.grainVoices {
            let voice = AVAudioPlayerNode()
            engine.attach(voice)
            engine.connect(voice, to: engine.mainMixerNode, format: format)
            voices.append(voice)
        }
    }

    /// Starts the engine if it is not running (first use, or after a phone call or a trip to the background).
    private func wake() -> Bool {
        load()
        guard !failed else { return false }
        if engine.isRunning { return true }
        do {
            try engine.start()
        } catch {
            return false
        }
        for (name, loop) in loops {
            loop.player.stop()
            loop.player.volume = 0
            loop.player.scheduleBuffer(loop.buffer, at: nil, options: .loops)
            loop.player.play()
            loops[name]?.volume = 0
        }
        for voice in voices { voice.stop() }
        return true
    }

    /// Once a frame while a soft squishy is on screen. `pan` is where the toy is, -1...1.
    func play(_ frame: SquishSoundMixer.Frame, pan: Double, dt: Double, enabled: Bool) {
        guard enabled else {
            rest()
            return
        }
        guard wake() else { return }
        // Volumes glide over about 35 ms, so nothing clicks.
        let ease = Float(1 - exp(-dt / 0.035))
        for (name, loop) in loops {
            let target = Float(frame.loops[name] ?? 0)
            let volume = loop.volume + (target - loop.volume) * ease
            loops[name]?.volume = volume
            loop.player.volume = volume < 0.0005 ? 0 : volume
            loop.player.pan = Float(pan)
        }
        for grain in frame.grains {
            guard let set = grains[grain.set], let buffer = set.randomElement() else { continue }
            fire(buffer, volume: grain.volume, pan: pan + grain.pan)
        }
        if let thud = frame.thud, let buffer = oneShots["thud"] { fire(buffer, volume: thud, pan: pan) }
    }

    func pop(volume: Double, pan: Double, enabled: Bool) {
        guard enabled, wake(), let buffer = oneShots["pop"] else { return }
        fire(buffer, volume: volume, pan: pan)
    }

    private func fire(_ buffer: AVAudioPCMBuffer, volume: Double, pan: Double) {
        guard !voices.isEmpty, volume > 0.002 else { return }
        let voice = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        voice.volume = Float(min(1, volume))
        voice.pan = Float(max(-1, min(1, pan)))
        voice.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !voice.isPlaying { voice.play() }
    }

    /// No soft squishy on screen: go quiet and let the audio hardware sleep.
    func rest() {
        guard loaded, engine.isRunning else { return }
        for (name, loop) in loops {
            loop.player.volume = 0
            loops[name]?.volume = 0
        }
        engine.pause()
    }
}
