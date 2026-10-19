# 鸡丝上班搭子 JisiBuddy

鸡丝是一只橘猫上班搭子。个人自用原型，iOS 17+，SwiftUI 原生。

## 结构

| 目录 | 内容 |
| --- | --- |
| `JisiKit/` | 本地 Swift Package：模型、CatBrain 状态引擎、App Group 存储、SwiftData 日志、App Intents、ActivityAttributes、`JisiCatView`（头像 + 程序动画） |
| `JisiApp/` | App：首页小窝、设置、本地提醒 |
| `JisiWidgets/` | Widget Extension：锁屏 Widget（rectangular / circular）+ Live Activity / 灵动岛 |
| `Config/` | entitlements（App Group `group.com.zixu.jisibuddy`）、扩展 Info.plist |
| `scripts/` | `test-kit.sh` 跑单元测试，`import-jisi.sh` 导入鸡丝头像，`gen-xcodeproj.py` 生成工程 |

## 常用

```sh
scripts/test-kit.sh                          # JisiKit 单元测试
scripts/import-jisi.sh ~/Downloads/鸡丝.png   # 导入头像（自动水平翻转、缩到 512px）
xcodebuild -project JisiBuddy.xcodeproj -scheme JisiApp -destination 'generic/platform=iOS Simulator' build
```

签名：Xcode 里给 JisiApp、JisiWidgets 两个 target 选你的个人团队；如果 bundle id 冲突，改 `com.zixu.jisibuddy` 前缀（App Group id 在 `Config/*.entitlements` 和 `JisiConfig.appGroupID` 里要同步改）。

## 已知限制（2026-10-19 iPhone 16 Pro Max / iOS 27 实测）

- 锁屏卡片（Live Activity）上的按钮：手机锁着时点按钮会先要求面容 ID，认证后直接在锁屏执行，不会打开 App。按钮的 intent 已设为 `authenticationPolicy = .alwaysAllowed`（打包后的元数据里确认生效），所以这一步是 iOS 自己要求的。
- 锁屏小组件（accessoryRectangular / accessoryCircular）只能单色显示，用户觉得不好看，已暂时隐藏；代码和单色高对比度头像 `JisiFaceMono.png` 都保留着，在 `LockScreenWidget.swift` 的 `supportedFamilies` 里加回来就能恢复。主屏幕 / 待机用彩色的 systemSmall 小组件。
- 免费开发者账号签的 App 大约 7 天后会过期，需要重新编译安装。
