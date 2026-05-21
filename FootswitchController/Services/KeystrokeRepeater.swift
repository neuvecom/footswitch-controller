import Foundation
import OSLog

private let logger = Logger(subsystem: "com.luckysama.footswitch-controller", category: "repeater")

/// 一定時間で自動停止する連射を管理する。
///
/// ペダルを踏むと指定キーを一定間隔で連送開始し、指定の継続時間が過ぎたら自動停止する。
/// 連射中にもう一度踏むと継続時間がリセットされて延長される (踏み続ければ伸び、踏むのを
/// やめれば時間で勝手に止まる)。停止のための踏み直しは不要。
///
/// キー単位 (keyCode + modifiers) で管理するので、別アプリ・別ボタンで複数の連射を
/// 同時に走らせられる。連射対象はキーストロークのみ (URL/Shell 等の暴走を防ぐため)。
@MainActor
final class KeystrokeRepeater {

    private struct RepeatKey: Hashable {
        let keyCode: UInt16
        let modifiers: UInt
    }

    private struct Running {
        let repeatTimer: Timer
        var stopTimer: Timer
    }

    private var active: [RepeatKey: Running] = [:]

    /// 連射をトリガーする。未稼働なら開始、稼働中なら継続時間を延長する。
    func trigger(keyCode: UInt16, modifiers: ModifierSet, intervalMs: Int, durationMs: Int) {
        let key = RepeatKey(keyCode: keyCode, modifiers: modifiers.rawValue)
        let duration = max(0.1, Double(durationMs) / 1000.0)

        // 稼働中: 停止タイマーだけ張り直して延長。連射タイマーはそのまま継続。
        if var running = active[key] {
            running.stopTimer.invalidate()
            running.stopTimer = makeStopTimer(key: key, duration: duration)
            active[key] = running
            logger.info("repeat EXTEND keyCode=\(keyCode, privacy: .public) +\(duration, privacy: .public)s")
            return
        }

        let interval = max(0.02, Double(intervalMs) / 1000.0)
        logger.info("repeat START keyCode=\(keyCode, privacy: .public) interval=\(interval, privacy: .public)s duration=\(duration, privacy: .public)s")

        // 初回はフットスイッチ自身の F13 keyUp が通過するのを待ってから送る。
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(40)) { [weak self] in
            guard let self, self.active[key] != nil else { return }
            ActionExecutor.sendKeystrokeImmediate(keyCode: keyCode, modifiers: modifiers)
        }

        let repeatTimer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated {
                ActionExecutor.sendKeystrokeImmediate(keyCode: keyCode, modifiers: modifiers)
            }
        }
        RunLoop.main.add(repeatTimer, forMode: .common)

        let stopTimer = makeStopTimer(key: key, duration: duration)
        active[key] = Running(repeatTimer: repeatTimer, stopTimer: stopTimer)
    }

    private func makeStopTimer(key: RepeatKey, duration: TimeInterval) -> Timer {
        let timer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stop(key: key)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private func stop(key: RepeatKey) {
        guard let running = active[key] else { return }
        running.repeatTimer.invalidate()
        running.stopTimer.invalidate()
        active[key] = nil
        logger.info("repeat STOP keyCode=\(key.keyCode, privacy: .public)")
    }

    /// すべての連射を停止する。
    func stopAll() {
        for running in active.values {
            running.repeatTimer.invalidate()
            running.stopTimer.invalidate()
        }
        active.removeAll()
    }
}
