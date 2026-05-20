# footswitch-controller

PC Sensor FS23 (3ボタン USB フットスイッチ) 用の macOS メニューバー常駐コントローラー。

フットスイッチが送出するキーボードイベントを横取りして、アクティブなアプリ／ユーザー定義のモードごとに任意のアクション (キー送出・URL 起動・スクリプト実行など) に置き換える。

## デバイス仕様

PC Sensor FS23 は USB HID キーボードとしてマウントされ、各ボタンを押すと固定のキーストロークを送出する。

| ボタン | キー | KeyCode | NSEvent modifierFlags (10進) | NSEvent modifierFlags (16進) | 内訳 |
| --- | --- | --- | --- | --- | --- |
| 1 | F13 | 105 | 8388864 | 0x800100 | function |
| 2 | Option + F13 | 105 | 8913184 | 0x880120 | function + option |
| 3 | Ctrl + F13 | 105 | 8651009 | 0x840101 | function + control |

メモ:
- すべて keyCode = 105 (`kVK_F13`) を送る。区別は modifier のみ。
- 上位ビットは `NSEvent.ModifierFlags` の `function (0x800000)` / `option (0x80000)` / `control (0x40000)`。下位 0x100 系のビットはデバイス依存フラグなので判定では無視する。
- `CGEventTap` で受ける場合は `CGEventFlags` で `.maskAlternate` / `.maskControl` を見る。

## アプリ要件

### 実装済み
- [x] メニューバー常駐 (SwiftUI `MenuBarExtra`)
- [x] グローバルキー監視 (`CGEventTap`) で F13 / Option+F13 / Ctrl+F13 を検知
- [x] 検知したボタンと送出元アプリ (frontmost) をログとして UI に出す
- [x] Accessibility 権限の案内 + プロンプト
- [x] frontmost アプリ監視 (`NSWorkspace.didActivateApplicationNotification`)
- [x] アプリごとに 3 ボタンのアクションを設定
- [x] 1 アプリ内の複数モード + モード切替
- [x] アクション種別: キーストローク / URL / Shell / AppleScript / モード切替 / なし
- [x] 設定 GUI (独立 NSWindow + SwiftUI)
- [x] 設定の永続化 (JSON @ `~/Library/Application Support/<bundleID>/settings.json`)

### 未実装 / 既知の制限
- キーストローク編集はプリセット keyCode + 修飾キーチェックボックスのみ。NSEvent ベースの「録音」UI は次フェーズ。
- メニュー項目を叩くアクション (Accessibility 経由) は未実装。
- `cycleMode` (現在モードから次へ巡回) は未実装。`switchMode(modeID)` のみ。
- リリース時の公証 (notarize) / Hardened Runtime 完全対応は未対応。
- ループ防止のため `keyCode == 105 (F13)` の送出は ActionExecutor 側で禁止している。

## アーキテクチャ

```
FootswitchController.app
├── FootswitchControllerApp.swift     App entry + DI
├── KeyEventMonitor.swift             CGEventTap on dedicated RunLoop thread
├── MenuBarContentView.swift          メニューバー UI
├── Models/
│   ├── Action.swift                  FootswitchAction enum + ModifierSet + KeyCodes
│   ├── Profile.swift                 Profile / Mode
│   └── SettingsStore.swift           ObservableObject + JSON 永続化
├── Services/
│   ├── AppWatcher.swift              frontmost app の購読
│   ├── ActionExecutor.swift          Keystroke / URL / Shell / AppleScript 実行
│   └── ActionDispatcher.swift        KeyEventMonitor → AppWatcher → Store → Executor
└── UI/
    ├── SettingsWindowController.swift  NSWindow ホスト
    ├── SettingsView.swift              プロフィール/モード一覧 + 編集
    └── ActionEditor.swift              1 Action 用フォーム
```

## 動作のキモ

- **CGEventTap は専用スレッドの RunLoop で回す**。メインの RunLoop に張ると `MenuBarExtra` の処理でブロックされて OS から自動 disable される (`tapDisabledByTimeout`)。
- **検知タップは `.cgSessionEventTap`** を使う。これは**アクセシビリティ権限**で動く。`.cghidEventTap` は別途**入力監視 (Input Monitoring) 権限**が必要になるので避ける。session tap でも 3 ボタン (F13 / Option+F13 / Ctrl+F13) すべて検知できることは検証済み。
- **frontmost 判定は `NSWorkspace.shared.frontmostApplication`** をベースに `didActivateApplicationNotification` で更新。自分自身 (FootswitchController) が前面のときは無視して直前のアプリを保持する (設定ウィンドウを開いた瞬間に frontmost が自分になるため)。
- **マッピング検索**: `frontmost.bundleID` 一致 → なければ Default Profile。
- **キーストローク送出**: `CGEvent(keyboardEventSource:virtualKey:keyDown:)` を `.combinedSessionState` で作り、フットスイッチの keyUp 通過を待つため 40ms 遅延してから `post(tap: .cghidEventTap)`。**アクセシビリティ権限**で動く。F13 (keyCode 105) は送出禁止 (自身の tap に戻りループするため)。

## 署名と権限 (重要 / ハマりどころ)

このアプリの動作には **アクセシビリティ権限 1 つだけ** が必要 (検知も送出も両方これで動く)。ただし以下の罠がある:

- **ad-hoc 署名 (`CODE_SIGN_IDENTITY="-"`) では `CGEvent.post` が silently drop される**。キーは送出できているように見えてターゲットに届かない。**Developer ID 署名 (証明書ベース) が必須**。署名すると post が効くようになる。
- **ad-hoc 署名はリビルドのたびに CDHash が変わり、TCC 権限が無効化される**。UI 上は `AXIsProcessTrusted()` が古いキャッシュで `true` を返すため「許可済み」に見えるが実際は効いていない。証明書ベース署名なら team + bundleID で識別され、リビルドしても権限が保持される。
- 過去に「System Events 経由 (AppleScript) でキー送出」を試したが、それには**オートメーション権限 + Hardened Runtime 下では `com.apple.security.automation.apple-events` entitlement** が必要になり権限が増える。Developer ID 署名で `CGEvent.post` が効くようになったので**この方式は廃止**した。
- 署名 ID: `Developer ID Application: Yoshiharu Sato (N957X4L8PY)`、Team ID `N957X4L8PY`。

## ビルド / 実行

xcodegen の `project.yml` に署名設定 (Manual / Developer ID / Team N957X4L8PY) が入っている。自動署名 (Automatic) は Apple ID ログインを要求してコマンドラインで失敗するため **Manual 署名**を使う。

```bash
xcodegen generate

xcodebuild -project FootswitchController.xcodeproj -scheme FootswitchController \
  -configuration Debug -derivedDataPath build \
  CODE_SIGN_STYLE=Manual \
  "CODE_SIGN_IDENTITY=Developer ID Application: Yoshiharu Sato (N957X4L8PY)" \
  PROVISIONING_PROFILE_SPECIFIER="" DEVELOPMENT_TEAM=N957X4L8PY build

# 実行 (権限を安定させるため /Applications に固定パスで置く)
cp -R build/Build/Products/Debug/FootswitchController.app /Applications/
open /Applications/FootswitchController.app
```

初回起動時、アクセシビリティ未許可ならオンボーディングウィンドウが自動表示される。許可は 1 秒ポーリングで自動検知され、付与された瞬間に監視を開始する (アプリ再起動不要)。

### デバッグ

- ログは `os.Logger` (subsystem `com.luckysama.footswitch-controller`)。`NSLog` は `log stream` のフィルタで拾いにくいので Logger を使う。
  ```bash
  log stream --predicate 'subsystem == "com.luckysama.footswitch-controller"' --info
  ```
- 権限を作り直したいとき: `tccutil reset Accessibility com.luckysama.footswitch-controller`

## 配布

- **Mac App Store は不可** (サンドボックス必須で CGEventTap / CGEvent.post が動かない)。
- **Developer ID 署名 + 公証 (notarytool) + DMG** で GitHub Releases 等から配布する (審査不要)。
- 公証〜DMG 化は `./scripts/release.sh [keychain-profile]` で全自動 (`dist/FootswitchController.dmg` を生成)。
  - 事前に一度だけ `xcrun notarytool store-credentials "footswitch-notary" --apple-id <id> --team-id N957X4L8PY --password <app用パスワード>` で認証情報を keychain に保存しておく。
  - app用パスワードは appleid.apple.com で生成。Developer Program の License Agreement に同意済みである必要がある (未同意だと 403)。
- **公証で必須の署名設定** (ハマった点):
  - `OTHER_CODE_SIGN_FLAGS=--timestamp` — secure timestamp。無いと Invalid。
  - `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` — `com.apple.security.get-task-allow` (debug 用 entitlement) を除外。付いていると Invalid。
  - Hardened Runtime 有効 + `com.apple.security.automation.apple-events` entitlement (entitlements ファイルに記載済み)。
- アップデート確認は軽量版 (GitHub Releases API) か Sparkle を予定 (未実装)。

## 開発メモ

- F13 はキーコード 105。フットスイッチは Fn ビット込みで送ってくるのでそのまま検知できる。3 ボタンの区別は `CGEventFlags` の `.maskAlternate` (Option) / `.maskControl` (Control) の有無のみ。
