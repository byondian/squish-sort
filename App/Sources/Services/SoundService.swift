import AVFoundation

/// Every game sound goes through here, so the Sound switch silences all of them.
/// The files are the starter set from the design thread; recorded squeaks can
/// replace them later under the same names.
@MainActor
final class SoundService {
    var enabled = true
    private var pools: [String: [AVAudioPlayer]] = [:]
    private var moveStep = 0
    private var lastMoveAt = Date.distantPast
    private var coinStep = 0

    init() {
        // Game sounds obey the silent switch and never stop the player's own music.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
    }

    func play(_ name: String, volume: Float = 1) {
        guard enabled else { return }
        var pool = pools[name] ?? []
        let player: AVAudioPlayer
        if let free = pool.first(where: { !$0.isPlaying }) {
            player = free
        } else {
            guard pool.count < 4, let url = Bundle.main.url(forResource: name, withExtension: "wav"),
                  let made = try? AVAudioPlayer(contentsOf: url) else { return }
            made.prepareToPlay()
            pool.append(made)
            pools[name] = pool
            player = made
        }
        player.volume = volume
        player.currentTime = 0
        player.play()
    }

    /// The squeak steps up one note per move while moves come quickly, and starts again after a pause.
    func move(run: Int) {
        let now = Date()
        moveStep = now.timeIntervalSince(lastMoveAt) <= 0.6 ? min(6, moveStep + 1) : 1
        lastMoveAt = now
        play("move_\(moveStep)")
        play("land_soft", volume: 0.5)
        if run >= 3 { play("run_x3") }
    }

    /// `number` is how many jars the level has finished so far, counting this one.
    func jarComplete(number: Int) {
        play("jar_complete_\(min(8, max(1, number)))")
        play("lid")
    }

    func coin() {
        coinStep = coinStep % 3 + 1
        play("coin_\(coinStep)")
    }

    func star(_ number: Int) { play("star_\(min(3, max(1, number)))") }
}
