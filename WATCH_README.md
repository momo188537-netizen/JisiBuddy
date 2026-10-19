# Apple Watch 第一档

分支 `watch-tier1`，未合进 `main`。手表上一个页面 + 表盘复杂功能，上班状态和 iPhone 双向同步。

## 改了什么

| 位置 | 内容 |
| --- | --- |
| `JisiKit/Sources/JisiWatchKit/` | 新的轻量模块，iPhone / 手表 App / 手表小组件共用：`WatchState`（上班状态）、`WatchCommand`（上班 / 一起下班请求）、`WatchCodec`（WatchConnectivity 字典 ⇄ JSON）、`WatchStateStore`（手表端 App Group）、`WatchCountdown`（倒计时纯函数）、`WatchCatFace`（头像 + 5 种表情）和 256 / 84px 头像图 |
| `JisiKit/Sources/JisiKit/WatchBridge.swift` | iPhone 会话 → `WatchState`；`jisiWorkStateDidChange` 通知 |
| `JisiKit/Sources/JisiKit/LiveActivity.swift` | `startWork(allowWithoutActivity:)`：手表发来「上班」时 App 可能在后台，系统不让开始实时活动，这时照样记下会话，回到 App 首页出现「继续陪伴」补上。上班 / 下班后发 `jisiWorkStateDidChange` |
| `JisiApp/PhoneWatchLink.swift` | iPhone 端 `WCSession`：状态变了就 `updateApplicationContext` 推给手表；收到手表请求走 `LiveActivityController.startWork / endWork`（和 App、Siri、控制中心同一套），实时活动、锁屏小组件、下班提醒照常更新。超过 15 分钟的排队请求丢弃 |
| `JisiApp/JisiApp.swift`、`Reminders.swift` | 启动时开 `PhoneWatchLink`；App 开着时手表操作后首页刷新 |
| `JisiWatch/` | 手表 App（`com.zixu.jisibuddy.watchkitapp`，watchOS 10.0+，嵌在 iOS App 里）：鸡丝头像（点一下换表情）、状态（还没上班 / 距下班倒计时 + 已上班多久 / 该下班啦）、大按钮「上班」/「一起下班」。点按钮先乐观更新再发给 iPhone：iPhone 可达用 `sendMessage` 等回复，不可达用 `transferUserInfo` 排队 |
| `JisiWatchWidgets/` | 表盘复杂功能（`com.zixu.jisibuddy.watchkitapp.widgets`）：圆形（鸡丝头像，上班时外圈是进度）、矩形（头像 + 距下班倒计时 + 下班时刻）、一行字、角落（头像 + 弧上倒计时）。倒计时用 `Text(timerInterval:)` 自己走秒；时间线只在到下班点换样式。染色表盘：`widgetAccentable`，watchOS 11+ 头像用 `accentedDesaturated` |
| `Config/JisiWatch*.entitlements`、`JisiWatchWidgets-Info.plist` | 手表两个 target 的 App Group 和扩展声明 |
| `scripts/gen-xcodeproj.py` | 加了两个手表 target、「Embed Watch Content」、`JisiWatch` scheme。工程已重新生成 |
| `scripts/import-jisi.sh` | 换头像时一起生成手表用的两张小图 |
| `JisiKit/Tests/JisiKitTests/WatchSyncTests.swift` | 19 个测试：同步消息编解码（含属性列表合法性）、旧状态不覆盖新状态、过期请求丢弃、乐观更新的下班点、iPhone 会话转换、倒计时 / 进度 / 文案、表情循环、头像资源 |

数据流：iPhone `SharedStore` → `updateApplicationContext` → 手表 `WatchModel` → 手表 App Group → `reloadAllTimelines` → 复杂功能。

通知：没加任何手表端通知代码，iPhone 的饭点 / 休息 / 下班提醒按系统规则镜像到手表（iPhone 锁屏、手表戴着时），「吃了」「休息了」「一起下班」按钮也会出现在手表上并回到 iPhone 执行。代码里没有阻止转发的设置（没用 passive 级别，带声音）。

## 验证

- `scripts/test-kit.sh`（macOS）：86 个测试全过；`xcodebuild -scheme JisiKit-Package test`（iOS 模拟器）：87 个全过
- `JisiWatch`（watchOS 模拟器）、`JisiApp`（iOS 模拟器、iOS 真机不签名）构建通过，无新警告；手表二进制含 arm64_32（Series 8 需要）
- 配对的 iPhone 18 Pro + Watch Series 12 模拟器上实测：手表点「上班」→ iPhone 首页变成陪伴中；iPhone 点「一起下班」→ 手表回到「还没上班」
- 表盘复杂功能只验证了编译，没在模拟器表盘上逐个看样式

## 装机步骤（iPhone 连上 Mac 后）

1. 手表：Series 8 已升级 watchOS 26.6，打开「设置 > 隐私与安全性 > 开发者模式」（第一次需要先在 Xcode 里连过手表才会出现这个开关），iPhone 也要开开发者模式。
2. Xcode 打开 `JisiBuddy.xcodeproj`，四个 target（JisiApp、JisiWidgets、JisiWatch、JisiWatchWidgets）的 Signing 都选个人团队 `BY5X8QUWJ3`（已写在工程里，确认一下即可）。
3. 手机用线连 Mac 并解锁，手表和手机在身边、手表解锁并戴着或放在充电器上。Xcode 「Window > Devices and Simulators」等手表出现并准备完成（第一次可能要十几分钟）。
4. 选 `JisiApp` scheme、目标选你的 iPhone，Run。手表 App 会跟着装（嵌在 iOS App 里）。如果手表上没出现，iPhone「Watch」App > 我的手表 > 往下翻找「鸡丝」点安装。也可以选 `JisiWatch` scheme、目标选手表直接装。
5. 表盘：长按表盘 > 编辑 > 复杂功能，选「鸡丝」。
6. 免费团队签名 7 天过期，到期后重新 Run 一次（手机和手表一起续）。

## 风险

- **免费团队 App ID 数量**：现在一共 4 个 bundle id（App、锁屏小组件、手表 App、手表小组件）。免费账号每 7 天最多注册 10 个 App ID，第一次签手表时会新注册 2 个；如果 Xcode 报超限，等几天或把 bundle id 前缀改成之前用过的。
- **App Group 签不出来**：免费团队的 App Group 有时签不上。手表 App 和复杂功能就各自用自己的 UserDefaults，复杂功能会一直显示「还没上班」（手表 App 本身不受影响）。
- **后台上班没有实时活动**：手表点「上班」时如果 iPhone App 不在前台，iOS 不允许开始实时活动，会话照样开始、下班提醒照样排，但锁屏上暂时没有鸡丝卡片，打开一次 App 点「继续陪伴」补上。
- **小组件扩展进程里点的「一起下班」**（锁屏实时活动按钮）不会立刻推给手表，等 iPhone App 下次启动或回到前台时补推，手表那几分钟会显示还在上班。
- **iPhone 不在身边**：手表点按钮先显示新状态并提示「连上后同步」；请求排队超过 15 分钟才送到 iPhone 的会被丢弃，之后手表以 iPhone 推来的状态为准。
- 手表和 iPhone 的时钟如果差得多，「旧状态不覆盖新状态」可能误判；对自己请求的回复总是采纳，影响有限。
- 真机没测过（WatchConnectivity 在真机上的唤醒时机和模拟器不完全一样），第一次装好后建议手表点一次上班 / 下班、iPhone 点一次，确认两边都跟着变。
