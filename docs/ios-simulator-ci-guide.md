# 在 Windows 上跑 iOS 模拟器：本仓库的 CI 方案与操作指南

> 适用对象：在 Windows（无 Xcode / 无 Simulator）机器上开发 iOS App，但需要在**真实 iOS 模拟器**里运行 UI、截图、做回归测试的开发者。
>
> 本仓库（`E:\Code\manga-downloader`）就是按这套方案做的：本机 Windows 无法运行 dsh-ios 插件（会返回 `host runs win32`），所以把“跑模拟器”搬到了 GitHub Actions 的 macOS runner 上。
>
> **注意：本仓库是 public 仓库，且内容是成人向漫画客户端。为避免把站点画面公开到 GitHub，CI 只上传文本日志与测试结果，不上传任何截图/xcresult；Release 也只附 IPA。** 如果 fork 后想收集截图，请自行改 workflow 并把仓库设为 private，或只在本机查看。

---

## 1. 整体方案

```
Windows 开发机                          GitHub Actions (macos-26)
┌──────────────────┐    git push      ┌────────────────────────────┐
│ 改代码 / 发版脚本 │ ───────────────▶ │ Xcode 26.3 + iOS Simulator │
│ gh CLI           │                  │ xcodebuild test (XCUITest) │
│ gh run download  │ ◀─────────────── │ text logs only             │
└──────────────────┘   artifacts      └────────────────────────────┘
```

- **代码构建**：`xcodebuild`（Release，未签名 IPA）由 `.github/workflows/ios.yml` 完成。
- **模拟器 UI 测试**：`.github/workflows/ui-preview.yml`，在 macOS runner 上启动 iOS Simulator，跑 XCUITest；只上传文本日志，不上传截图。
- **发版**：下载 CI 产物 → `gh release create/upload`（只上传 IPA）。

本仓库实际文件：

| 文件 | 作用 |
| --- | --- |
| `.github/workflows/ui-preview.yml` | 启动最新 iOS 模拟器、跑 UI 测试（iOS 26 最低部署，无需旧系统 job） |
| `ios/project.yml` | 声明 `WnacgDownloaderUITests` target 和 test scheme |
| `ios/UITests/CategoryScreenUITests.swift` | 分类页自动化回归（自动加载/筛选/详情/阅读器） |
| `ios/UITests/AppWalkthroughUITests.swift` | 全 App 走查（各 tab、深浅色、搜索、解析） |
| `.github/workflows/ios.yml` | Release 编译 + 真实站点 smoke test + IPA 打包 |

优点：
- public 仓库的标准 runner 免费；private 仓库会消耗 Actions 额度；
- 每次结果可复现，日志可下载（本仓库不上传截图）；
- 能同时覆盖最新 iOS 与旧 iOS（本仓库覆盖 iOS 26.2 与 18.x）。

缺点：
- 单轮约 10 分钟；
- 无实时交互（不能像本地模拟器那样点一下看结果）；
- 依赖 GitHub 网络（国内需要代理，见 §7）。

---

## 2. 一次性配置

### 2.1 给 XcodeGen 项目加 UI Test target

`ios/project.yml`：

```yaml
targets:
  WnacgDownloader:
    type: application
    platform: iOS
    # ... 原有配置 ...

  WnacgDownloaderUITests:
    type: bundle.ui-testing
    platform: iOS
    deploymentTarget: "26.0"
    sources:
      - path: UITests
    dependencies:
      - target: WnacgDownloader
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.wancg.downloader.uitests
        TEST_TARGET_NAME: WnacgDownloader
        GENERATE_INFOPLIST_FILE: YES
        SWIFT_VERSION: "5.0"
        CODE_SIGN_STYLE: Automatic
        DEVELOPMENT_TEAM: ""

schemes:
  WnacgDownloader:
    build:
      targets:
        WnacgDownloader: all
    run:
      config: Debug
    archive:
      config: Release
    test:
      config: Debug
      targets:
        - WnacgDownloaderUITests
```

生成工程：

```bash
cd ios
brew install xcodegen
xcodegen generate
```

### 2.2 写第一个 UI 测试

`ios/UITests/AppWalkthroughUITests.swift` 的核心骨架：

```swift
import XCTest

final class AppWalkthroughUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true       // 失败后仍继续，便于一次收集多张截图
    }

    func testFullAppWalkthrough() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        // 首页依赖网络；等某个标志元素出现
        XCTAssertTrue(app.buttons["同人志"].waitForExistence(timeout: 120))
        capture(app, "ui-walk-01-home")
        dump(app, "HOME")

        // 点 tab（键盘弹出时会挡住 tab bar，先 dismissKeyboard）
        dismissKeyboard(app)
        app.tabBars.buttons["设置"].tap()
        sleep(2)
        capture(app, "ui-walk-02-settings")
        dump(app, "SETTINGS")
    }

    // 截图：写到模拟器应用的临时目录，workflow 再用 find 收集
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name).png")
        try? shot.pngRepresentation.write(to: url)
        print("SCREENSHOT_PATH: \(url.path)")
    }

    // 无障碍树：纯文本也能审查布局/文案/可点击元素
    private func dump(_ app: XCUIApplication, _ label: String) {
        print("=== \(label) ===")
        print(app.debugDescription)
        print("=== END \(label) ===")
    }

    private func dismissKeyboard(_ app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        let done = app.buttons["完成"].firstMatch
        if done.exists { done.tap() } else { app.swipeDown() }
        sleep(1)
    }
}
```

要点：
- **中文不需要键盘输入**：用 `english` 搜索/URL 输入即可；`typeText` 对非 ASCII 支持有限。
- **等待用 `waitForExistence`**，不要全靠 `sleep`；但等待网络页面时设置 30–120s 超时。
- **键盘会挡住 tab bar**：切 tab 前主动收起键盘（本仓库 App 的「解析作品」按钮也会主动收键盘，测试里再加一层保险）。
- **断言要检查行为**：例如解析后 `XCTAssertFalse(app.keyboards.firstMatch.exists)`，避免测试里自己点“完成”把回归问题掩盖掉。

### 2.3 Workflow：启动模拟器 + 跑测试 + 收产物

`.github/workflows/ui-preview.yml` 核心部分（完整文件见仓库）：

```yaml
name: UI Tests

on:
  push:
    branches: [main]
    paths:
      - 'ios/**'
      - '.github/workflows/ui-preview.yml'
  workflow_dispatch:

concurrency:
  group: ui-preview-${{ github.ref }}
  cancel-in-progress: true

permissions:
  contents: read

jobs:
  ui-tests:
    runs-on: macos-26
    timeout-minutes: 40
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode 26
        run: |
          sudo xcode-select -s /Applications/Xcode_26.3.app
          xcodebuild -version

      - name: Install XcodeGen
        run: brew install xcodegen

      - name: Generate Xcode project
        working-directory: ios
        run: xcodegen generate

      # 关键步骤：选择模拟器（见 §3）
      - name: Boot newest iOS simulator
        id: sim
        run: |
          # 输出格式：udid \t version \t name
          SELECTION="$(/usr/bin/python3 - <<'PY'
          # ... 见 §3 的完整脚本 ...
          PY
          )"
          IFS=$'\t' read -r DEVICE_ID IOS_VERSION DEVICE_NAME <<< "$SELECTION"
          echo "selected iOS $IOS_VERSION — $DEVICE_NAME ($DEVICE_ID)"
          xcrun simctl boot "$DEVICE_ID" || true
          xcrun simctl bootstatus "$DEVICE_ID" -b
          echo "device_id=$DEVICE_ID" >> "$GITHUB_OUTPUT"

      - name: Run UI tests
        working-directory: ios
        run: |
          set -o pipefail
          COMMON=(
            -project WnacgDownloader.xcodeproj
            -scheme WnacgDownloader
            -configuration Debug
            -destination "platform=iOS Simulator,id=${{ steps.sim.outputs.device_id }}"
            CODE_SIGNING_ALLOWED=NO
            CODE_SIGNING_REQUIRED=NO
            CODE_SIGN_IDENTITY=
            DEVELOPMENT_TEAM=
          )
          # 两套测试分开跑：walkthrough 会大量访问真实站点，
          # 紧接其后的分类页测试曾经因此吃到 429 / 空首页。
          xcodebuild test "${COMMON[@]}" \
            -only-testing:WnacgDownloaderUITests/CategoryScreenUITests \
            | tee category-test.log
          xcodebuild test "${COMMON[@]}" \
            -only-testing:WnacgDownloaderUITests/AppWalkthroughUITests \
            | tee ui-test.log

      - name: Collect app logs
        if: always()
        working-directory: ios
        run: |
          xcrun simctl spawn "${{ steps.sim.outputs.device_id }}" \
            log show --last 15m --style compact \
            --predicate 'process == "WnacgDownloader"' \
            > app.log 2>/dev/null || true

      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: app-log
          path: ios/app.log

      - uses: actions/upload-artifact@v4
        if: failure()
        with:
          name: ui-test-failure
          path: |
            ios/category-test.log
            ios/ui-test.log
```

注意：
- **不生成/上传截图与 `.xcresult`**：public 仓库不适合公开站点画面；失败时只上传文本日志。
- 需要截图时，在 `private` fork 或本机加回 XCTAttachment / `xcresult`。
- `permissions: contents: read` 足够；无需签名，`CODE_SIGNING_ALLOWED=NO` 即可在模拟器运行。

---

## 3. 关键：选择正确的模拟器 runtime

`xcrun simctl list devices available -j` 返回的设备顺序**不保证是最新的**。本仓库最初就踩过坑：取列表第一台，结果是 **iPhone 16 Pro / iOS 18.5**，于是截图全是 iOS 18 风格；后来显式按 runtime 版本排序才切到 **iOS 26.2 / iPhone 17 Pro**。

### 3.1 选最新 iOS（主 job）

```bash
/usr/bin/python3 - <<'PY'
import json
import re
import subprocess

runtimes = json.loads(
    subprocess.check_output(["xcrun", "simctl", "list", "runtimes", "-j"])
)["runtimes"]

def version_key(rt):
    m = re.match(r"(\d+)(?:\.(\d+))?", rt.get("version", "0"))
    return (int(m.group(1)), int(m.group(2) or 0)) if m else (0, 0)

ios = sorted(
    [r for r in runtimes if r.get("isAvailable") and r.get("platform") == "iOS"],
    key=version_key,
    reverse=True,
)
rt = ios[0]
devices = json.loads(
    subprocess.check_output(["xcrun", "simctl", "list", "devices", "-j"])
)["devices"].get(rt["identifier"], [])
phones = [d for d in devices if d.get("isAvailable") and "iPhone" in d["name"]]
pros = [d for d in phones if "Pro" in d["name"]]
device = (pros or phones)[0]
print(f"{device['udid']}\t{rt['version']}\t{device['name']}")
PY
```

用输出中的 udid 作为 `-destination 'platform=iOS Simulator,id=<udid>'`。

### 3.2 旧 iOS runtime（本仓库已不再需要）

本仓库自 **1.25.0** 起最低部署版本为 **iOS 26**（低于 26 无法安装），因此只跑最新 iOS runtime，`ui-preview.yml` 里原来的 `legacy-runtime` job 已移除。

如果其他项目仍需兼容旧系统，可以保留类似 job：把升序脚本（`reverse=False`）选出的最旧 runtime 作为 destination，用 `-only-testing:` 只跑核心回归，并把 deployment target 相应降低。

---

## 4. 在 Windows 上触发、查看和拿结果

### 4.1 触发

```powershell
# 方式 1：push 到 main（workflow 里配了 paths: ios/**）
git push origin main

# 方式 2：手动触发任意分支
gh workflow run ui-preview.yml --ref main -R 2744317644/wancg-downloader
```

### 4.2 查看

```powershell
gh run list -R 2744317644/wancg-downloader --limit 5
gh run watch <run-id> -R 2744317644/wancg-downloader
gh run view <run-id> -R 2744317644/wancg-downloader --log > ui.log
```

日志里可以看到：
- `selected iOS 26.2 — iPhone 17 Pro ...`
- `Test Case ... passed/failed`
- `SCREENSHOT_PATH: ...`
- 测试里 `print(app.debugDescription)` 输出的无障碍树。

### 4.3 下载日志

```powershell
# 应用侧日志
gh run download <run-id> -R 2744317644/wancg-downloader `
  -n app-log -D .\artifacts\logs

# 测试失败时的日志
gh run download <run-id> -R 2744317644/wancg-downloader `
  -n ui-test-failure -D .\artifacts\failure
```

> 本仓库是 public 且有成人向内容，**CI 不生成/上传截图与 `.xcresult`**，只保留文本日志；截图策略见 §7.5。

### 4.4 无障碍树怎么看

测试输出的 `app.debugDescription` 会包含每个元素的类型、label、identifier、frame，例如：

```
Button, 0x103e55a90, {{323.0, 140.0}, {47.0, 29.0}}, label: '从剪贴板粘贴链接'
TabBar, 0x101b4e0a0, {{0.0, 791.0}, {402.0, 83.0}}, label: 'Tab Bar'
```

即使看不到图，也能据此判断：
- 控件是否在屏幕内、是否过小（<44pt）、是否重叠；
- 文案是否被截断（例如 label 里出现 `…`）；
- tab bar 是否只有一条、页面元素层级是否正确。

---

## 5. 把 CI 产物变成可发布的 Release（本仓库流程）

1. `ios.yml` 在 push main / 手动触发时构建 unsigned IPA，artifact 名为 `WnacgDownloader-unsigned-ipa`。
2. Windows 下载并校验版本：

```powershell
gh run download <build-run-id> -R 2744317644/wancg-downloader `
  -n WnacgDownloader-unsigned-ipa -D .\artifacts\ipa

# 校验 Info.plist 中的版本（二进制 plist，用 ASCII 搜索即可）
$ipa = ".\artifacts\ipa\WnacgDownloader-unsigned.ipa"
$tmp = "$env:TEMP\ipa-check"; Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive $ipa -DestinationPath $tmp
$plist = Get-ChildItem "$tmp\Payload\*.app\Info.plist" | Select-Object -First 1
$bytes = [IO.File]::ReadAllBytes($plist.FullName)
$text = [Text.Encoding]::ASCII.GetString($bytes)
if ($text -match '1\.23\.0') { "version OK" }
```

3. 创建 release 并上传：

```powershell
gh release create v1.23.0 -R 2744317644/wancg-downloader `
  --target main `
  --title "v1.23.0 - ..." `
  --notes-file .\release-notes-1.23.0.md `
  --latest `
  ".\artifacts\ipa\WnacgDownloader-unsigned.ipa"
```

> 本仓库的 Release **只上传 IPA，不附截图**（如图片必须保留，请改用 private 仓库）。

> 如果 `gh release create` 报 `tag_name is not a valid tag` 且你传的是短 commit SHA，改用 `--target main`（或完整 40 位 SHA）。

---

## 6. 本机（Windows）的替代能力边界

| 需求 | Windows 本机 | GitHub Actions macOS |
| --- | --- | --- |
| 编译 iOS App | ❌（无 Xcode） | ✅ |
| 启动 iOS Simulator | ❌ | ✅ |
| 交互式点按/输入 | ❌（dsh-ios 返回 host runs win32） | ⚠️ 只能通过 XCUITest 脚本 |
| 截图 | ❌ | ⚠️ 测试内可截图，但本仓库 CI/Release 不上传 |
| 崩溃/系统日志 | ❌ | ✅（`simctl spawn log show`） |
| Instruments 性能分析 | ❌ | ⚠️ 可跑但结果需 Mac 阅读/导出 |

如果你**有 Mac**：
- 直接用本仓库的 `ios/project.yml` 生成工程，Xcode 运行；
- dsh-ios 插件工具（`ios_sim_boot` / `ios_sim_launch_app` / `ios_sim_find_text` 等）可交互式驱动本机模拟器；
- 也可以直接 `xcrun simctl list devices` + `xcodebuild test -destination ...` 复现 CI 中的行为。

---

## 7. 常见问题与修复

### 7.1 GitHub 连不上（国内）

本机曾多次 `git push` / `fetch` 超时，但 API（api.github.com）可用。方案：

```powershell
# 如果有本地代理（如 Clash 7890 端口）
git config --local http.proxy http://127.0.0.1:7890
git config --local https.proxy http://127.0.0.1:7890
git push origin main
```

`gh` 命令走系统代理即可；若 API 也失败，可临时用 `HTTPS_PROXY=http://127.0.0.1:7890`。

### 7.2 选到的模拟器不是最新 iOS

原因：`simctl list` 的设备顺序不可靠。修复：按 `runtimes -j` 的 `version` 排序显式选择（见 §3）。

### 7.3 键盘挡住 tab bar / 点击被吞

- 切 tab 前先 `dismissKeyboard`；
- App 内点「解析作品」等动作应主动 `@FocusState` 收起键盘；
- UI 测试里加断言：`XCTAssertFalse(app.keyboards.firstMatch.exists)`，避免测试自己点“完成”掩盖回归。

### 7.4 测试超时

- 每个网络等待都给 `waitForExistence(timeout:)`（30–120s），不要全 `sleep`；
- job `timeout-minutes: 40`；
- 本仓库把 `CategoryScreenUITests` 与 `AppWalkthroughUITests` 分成两次 `xcodebuild test` 跑（避免 walkthrough 的站点流量导致后面分类页 429）；总时长约 6–9 分钟。

### 7.5 截图策略（本仓库不上传截图）

- 因为仓库 public 且内容是成人向漫画客户端，**不在 GitHub 上存储任何站点截图**：
  - Release 只附 IPA；
  - Actions 只上传文本日志（`app-log`、`ui-test-failure`），不上传截图或 `.xcresult`；
- 本机（Mac）可用 dsh-ios / `xcrun simctl io screenshot` 截图查看；
- 若确实需要 CI 截图，请把仓库设为 private，或在 fork 里自行加回 `actions/upload-artifact` 并承担公开风险。

### 7.6 编码 / 中文

- Windows 上用 PowerShell 的 `Get-Content/Set-Content` 批量改文件可能把 UTF-8 中文写成乱码（本仓库踩过：`用于连接...` 变成 `鐢ㄤ簬...` 并把 Swift 字符串搞成 unterminated literal）；
- 批量改文本用 UTF-8 无 BOM（`[IO.File]::WriteAllText($p, $text, [Text.UTF8Encoding]::new($false))`），或用编辑器/工具；
- 中文 UI 测试字符串没问题，但不要用 `typeText` 输入中文（模拟器键盘限制）。

### 7.7 视频/真机

这套方案只覆盖模拟器。真机安装需要签名（本项目输出 unsigned IPA，用 Sideloadly/AltStore 签名安装）；真机 UI 自动化需要 WebDriverAgent + Mac，Windows 上不可用。

---

## 8. 最小落地清单

- [ ] `project.yml` 增加 `bundle.ui-testing` target + scheme test 配置
- [ ] `ios/UITests/*.swift`：断言行为 + dump 无障碍树（截图仅写本机临时目录，不上传）
- [ ] workflow：选择最新 iOS runtime（§3）、`xcodebuild test`、上传文本日志
- [ ] push main 的 `ios/**` 自动触发 + 支持 `workflow_dispatch`
- [ ] 失败时仍上传测试日志（不含截图/xcresult）
- [ ] Windows 侧用 `gh run download` 取日志 + `gh release create` 发版（只传 IPA）
- [ ] 需要旧系统覆盖时再加回 `legacy-runtime` job（本仓库 iOS 26+，已移除）

---

## 9. 参考文件

- 本仓库 workflow：`.github/workflows/ui-preview.yml`
- 本仓库 UI 测试：`ios/UITests/CategoryScreenUITests.swift`、`ios/UITests/AppWalkthroughUITests.swift`
- 本仓库工程配置：`ios/project.yml`
- 技能库：`E:\Code\Skills`（`ios-debugger-agent`、`swiftui-ui-patterns` 等；本方案不依赖 XcodeBuildMCP，但在 Mac 上可用）
