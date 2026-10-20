# Mac 菜单栏鸡丝

分支 `mac-menubar`（从 `watch-tier1` 开出来，都还没合进 `main`）。原生 macOS 菜单栏 App（SwiftUI `MenuBarExtra`，不是 Catalyst），和 iPhone 在同一个 Wi-Fi 下自动同步，iPhone 再照原来的路同步给手表。

## 能做什么

菜单栏上是鸡丝的头像（睡觉 / 打盹时换闭眼照），上班时旁边显示离下班还有多久。点开小窗：

- 鸡丝在干嘛：台词、会动的头像（和 iPhone 同一个 `JisiCatView` / `CatBrain`）、当前动作
- 距下班倒计时、已陪伴多久；「带鸡丝上班」/「一起下班」，下班后问一句今天累不累（可跳过）
- 摸摸（也可以直接点鸡丝）、喂小鱼干、玩已得到的毛线球 / 纸箱 / 软垫
- 上班时「我在开会」30 / 60 / 90 分钟，开会中可提前结束
- 今天的小事一行、和 iPhone 的连接状态、退出

## 同步怎么走

| 位置 | 内容 |
| --- | --- |
| `JisiKit/Sources/JisiKit/PeerSync.swift` | 协议：`PeerSnapshot`（iPhone → Mac，会话、作息、互动、事件、纪念、开会）、`PeerCommand`（Mac → iPhone）、`PeerCodec`（4 字节长度 + JSON）、`PeerMerge`（后写者为准）、`PeerLocal`（Mac 本地先执行） |
| `JisiKit/Sources/JisiKit/PeerLink.swift` | Network.framework：`PeerHost`（Mac，Bonjour `_jisibuddy._tcp` 一直监听）、`PeerClient`（iPhone，前台时找 Mac 连上）。MultipeerConnectivity 在 27 SDK 里已废弃，没用它 |
| `JisiApp/PhoneMacLink.swift` | iPhone 端：连上后推一份状态；状态一变（上下班、摸摸、作息、开会）就推；Mac 的请求按顺序执行，走 `LiveActivityController` / `JisiActions` / `MeetingMode`，执行完回复，同时照常推给手表 |
| `JisiMac/` | Mac App：`MacModel`（本地状态 + 待发队列，存盘）、`MenuView`、`JisiMacApp`（菜单栏图标） |

- **后写者为准**：Mac 上点的先在本地生效，放进待发队列（退出 App 也不丢）；iPhone 连上时发过去，回复全部到齐后 Mac 才整份采纳 iPhone 的状态。iPhone 只执行比自己最近一次上下班更晚的上班 / 下班（12 小时内），按 Mac 上点的时间记；摸摸、喂食 24 小时内的都记。重连后重发的请求 iPhone 按 id 去重。
- **iPhone 是准**：实时活动、下班提醒、手表都在 iPhone 上。Mac 点「上班」时 iPhone App 在后台的话，和手表一样会发通知「点一下放到锁屏」。
- **只在 iPhone App 在前台时同步**：iOS 退后台会断开（系统限制），回到前台几秒内自动重连、互相补齐。手表上点的上下班要等 iPhone 打开鸡丝后才到 Mac。
- 没有配对 / 加密：同一个 Wi-Fi 下谁装了这个 App 都能连上（只有你自己有），传的只是上班状态。

## 签名

Mac App 不开沙盒、没有任何 entitlement，用 Apple Development 证书直接签，不需要描述文件，所以**没有 7 天过期**；证书 2027-10-19 到期，到时重新编译安装。iPhone 端仍是免费团队，7 天要重装一次（加了 `NSLocalNetworkUsageDescription`、`NSBonjourServices`，见 `Config/JisiApp-Info.plist`）。

## 验证

- `scripts/test-kit.sh`：112 个测试全过（新增 `PeerSyncTests` 10 个：编解码、帧长度、后写者为准、本地执行、整份采纳）；iOS 模拟器 `JisiKit-Package`：113 个全过
- `JisiMac`、`JisiApp`（模拟器 / 真机）、`JisiWatch` 构建通过
- Mac App + iPhone 18 Pro 模拟器实测：iPhone 状态同步到 Mac；Mac 离线时排队的「上班」连上后在 iPhone 上开始会话（开始时间 = Mac 上点的时间）；之后一条过时的「上班」被正确忽略；Mac → iPhone「一起下班」执行并回复
- 真机：已装到 iPhone，Mac App 装在 /Applications 并已打开；真机之间的连接要等你在两边点「允许」本地网络后才能测

## 安装 / 重装

```sh
xcodebuild -project JisiBuddy.xcodeproj -scheme JisiMac -configuration Release -derivedDataPath /tmp/jisi-dd build
ditto "/tmp/jisi-dd/Build/Products/Release/鸡丝.app" "/Applications/鸡丝.app"
```

开机自启：系统设置 > 通用 > 登录项 > 加上「鸡丝」。

调试：Debug 版 `鸡丝.app/Contents/MacOS/鸡丝 --render-menu out.png` 把小窗画成图片（菜单、无边框按钮会显示成占位块）。
