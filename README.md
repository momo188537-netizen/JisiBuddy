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
