import AppKit
import Combine
import Foundation
import OSLog

private let tapLogger = Logger(subsystem: "com.luckysama.footswitch-controller", category: "tap")

/// Footswitch のボタン種別。
///
/// 1 台目は F13 (keyCode 105) を、2 台目は F18 (keyCode 79) を送る前提。
/// 修飾キー (Option / Control) の有無で各 3 ボタンを判別する。
enum FootswitchButton: String, CaseIterable, Identifiable {
    case button1 = "Device 1: Button 1 (F13)"
    case button2 = "Device 1: Button 2 (Option+F13)"
    case button3 = "Device 1: Button 3 (Ctrl+F13)"
    case button4 = "Device 2: Button 1 (F18)"
    case button5 = "Device 2: Button 2 (Option+F18)"
    case button6 = "Device 2: Button 3 (Ctrl+F18)"

    var id: String { rawValue }

    /// このボタンが属するデバイス番号 (1 or 2)。
    var deviceIndex: Int {
        switch self {
        case .button1, .button2, .button3: return 1
        case .button4, .button5, .button6: return 2
        }
    }
}

/// 監視ログの 1 行。
///
/// 通常モードでは `button != nil` のフットスイッチ判定済みイベントのみ積まれる。
/// デバッグモードでは `button == nil` の生イベントも積まれ、keyCode/flags が見える。
struct FootswitchEvent: Identifiable {
    let id = UUID()
    let date: Date
    let button: FootswitchButton?
    let keyCode: Int64
    let flagsRaw: UInt64
    let frontmostApp: String

    var flagsHex: String { String(format: "0x%08llX", flagsRaw) }
}

/// グローバルキーフックを張って、フットスイッチからのキー入力だけを抜き出す。
///
/// PC Sensor FS23 は keyCode = 105 (F13) を、修飾キーの組み合わせで 3 種類に
/// 出し分ける。CGEventTap で `kCGHIDEventTap` を監視し、修飾キーから 3 ボタンを
/// 判別する。Accessibility 権限が必要。
///
/// イベントタップは専用スレッドの RunLoop で回す。メインの RunLoop に張ると、
/// SwiftUI / MenuBarExtra のポップアップ処理でブロックされた瞬間に OS から
/// "slow tap" と判定されてタップが自動 disable される。
final class KeyEventMonitor: ObservableObject {
    /// 検知履歴 (新しいものが先頭)。
    @Published private(set) var events: [FootswitchEvent] = []

    /// Accessibility 権限が確認できているか (キー検知・送出ともこれだけで動く)。
    @Published private(set) var hasAccessibilityPermission: Bool = false

    /// イベントタップが稼働中か。
    @Published private(set) var isRunning: Bool = false

    /// デバッグ: F13 フィルタを外して全 keyDown を記録する。
    @Published var debugLogAllKeys: Bool = false

    // タップ関連の状態はすべてタップスレッドから操作する。
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?

    private static let f13KeyCode: Int64 = 105  // device 1
    private static let f18KeyCode: Int64 = 79   // device 2 (F14/F15 はOS的に予約の可能性があるため F18 を採用)
    private static let maxEvents = 200

    private var permissionTimer: Timer?

    init() {
        refreshPermissionStatus()
        start()
        startPermissionPolling()
    }

    deinit {
        permissionTimer?.invalidate()
        stop()
    }

    /// アクセシビリティ権限はアプリに変更通知が来ないため、定期的にポーリングする。
    /// 未許可 → 許可に変わった瞬間に自動で監視を開始する。
    private func startPermissionPolling() {
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let trusted = AXIsProcessTrusted()
            self.hasAccessibilityPermission = trusted
            if trusted && !self.isRunning {
                self.stop()
                self.start()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    // MARK: - Permission

    /// Accessibility 権限の状態をチェックし、未許可なら設定アプリへのプロンプトを表示する。
    func requestPermissionIfNeeded() {
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        let trusted = AXIsProcessTrustedWithOptions(options)
        setPermissionState(trusted)
    }

    func refreshPermissionStatus() {
        setPermissionState(AXIsProcessTrusted())
    }

    private func setPermissionState(_ trusted: Bool) {
        if Thread.isMainThread {
            hasAccessibilityPermission = trusted
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.hasAccessibilityPermission = trusted
            }
        }
    }

    // MARK: - Tap lifecycle

    func start() {
        guard tapThread == nil else { return }

        let thread = Thread { [weak self] in
            self?.runTapOnCurrentThread()
        }
        thread.name = "FootswitchEventTap"
        thread.qualityOfService = .userInteractive
        tapThread = thread
        thread.start()
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoop = tapRunLoop {
            if let source = runLoopSource {
                CFRunLoopRemoveSource(runLoop, source, .commonModes)
            }
            CFRunLoopStop(runLoop)
        }
        eventTap = nil
        runLoopSource = nil
        tapRunLoop = nil
        tapThread = nil

        if Thread.isMainThread {
            isRunning = false
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.isRunning = false
            }
        }
    }

    private func runTapOnCurrentThread() {
        tapLogger.info("runTap start. trusted=\(AXIsProcessTrusted(), privacy: .public) bundle=\(Bundle.main.bundlePath, privacy: .public)")
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        // .cgSessionEventTap はアクセシビリティ権限で動く (入力監視権限は不要)。
        // (.cghidEventTap は入力監視権限が要る。session tap でボタン3 も取れることは検証済み)
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<KeyEventMonitor>.fromOpaque(refcon).takeUnretainedValue()
                monitor.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        )

        guard let tap else {
            // 多くの場合 Accessibility 権限が無い。
            tapLogger.error("tapCreate FAILED. trusted=\(AXIsProcessTrusted(), privacy: .public)")
            DispatchQueue.main.async { [weak self] in
                self?.refreshPermissionStatus()
                self?.tapThread = nil
            }
            return
        }
        tapLogger.info("tapCreate OK, enabled=\(CGEvent.tapIsEnabled(tap: tap), privacy: .public)")

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let runLoop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        tapRunLoop = runLoop

        DispatchQueue.main.async { [weak self] in
            self?.isRunning = true
            self?.hasAccessibilityPermission = true
        }

        // 専用スレッドでブロッキング実行。stop() で CFRunLoopStop されるまで戻らない。
        CFRunLoopRun()
    }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }
        guard type == .keyDown else { return }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let isF13 = (keyCode == Self.f13KeyCode)
        let isF18 = (keyCode == Self.f18KeyCode)
        let isFootswitchKey = isF13 || isF18

        // デバッグモード OFF かつ対象キー以外なら早期 return。
        if !debugLogAllKeys && !isFootswitchKey { return }

        let button: FootswitchButton?
        if isFootswitchKey {
            let hasOption = flags.contains(.maskAlternate)
            let hasControl = flags.contains(.maskControl)
            switch (isF13, hasOption, hasControl) {
            case (true,  false, false): button = .button1
            case (true,  true,  false): button = .button2
            case (true,  false, true):  button = .button3
            case (false, false, false): button = .button4
            case (false, true,  false): button = .button5
            case (false, false, true):  button = .button6
            default: button = nil // 仕様外 (両方の修飾 ON など)。デバッグログとしてだけ残す。
            }
        } else {
            button = nil
        }

        // 仕様外の組み合わせは、デバッグモード OFF なら捨てる。
        if !debugLogAllKeys && button == nil { return }

        let flagsRaw = flags.rawValue
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let frontmost = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
            let record = FootswitchEvent(
                date: Date(),
                button: button,
                keyCode: keyCode,
                flagsRaw: flagsRaw,
                frontmostApp: frontmost
            )
            self.events.insert(record, at: 0)
            if self.events.count > Self.maxEvents {
                self.events.removeLast(self.events.count - Self.maxEvents)
            }
        }
    }
}
