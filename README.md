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

## P1 设计

原则不变：没有等级、分数、金币、签到，不惩罚；鸡丝的脸一直是原来的照片，只加姿势、动作和道具。

### 小窝与物件

首页是固定视角的 2D 小窝：墙、窗、书桌（电脑、咖啡）、盆栽、地板。按作息分白天 / 傍晚 / 夜里三种光线（`SceneLight`），夜里窗外有月亮。

三件物件，都通过真实发生的事情得到（`NestGifts`），每次最多得一件，得到时首页提示一次：

| 物件 | 怎么得到 | 点它时鸡丝 | 自己会不会用 |
| --- | --- | --- | --- |
| 毛线球 | 第一次「带鸡丝上班」 | 拍毛线球，球滚来滚去（5 分钟） | 上班 / 下班后 / 周末摸鱼时会玩 |
| 纸箱 | 第一次在提醒里点「吃了」或「休息了」 | 钻进纸箱只露出头（5 分钟） | 同上 |
| 软垫 | 第一次「一起下班」 | 趴在软垫上打盹（5 分钟） | 午后犯困、睡前、夜里睡在软垫上 |

小惊喜：相处满 3 天（3 个有过互动的日子）时，还没得到的物件会被鸡丝「捡到」一件。

### 更丰富的自主行为

一天按作息分成 早上 / 上午上班 / 饭点 / 午后犯困 / 下午上班 / 下班后 / 睡前 / 夜里 / 休息日（`CatBrain.period`），每段有自己的台词池；动作有假装工作、睡键盘（午后困得趴在电脑上）、伸懒腰、喝咖啡、钓鱼、玩毛线球、钻纸箱、软垫打盹。同一天里相邻两个时间桶不重复，最近 6 句台词不重样。

### 纪念与回忆

`Diary` 只记真实发生的事：第一次记录的时间、有互动的日子、一起下班 / 吃饭 / 摸摸 / 喂食的次数、物件得到的时间。纪念（`Memory`）只写「什么时候发生了什么」，不推断情绪：

- 和鸡丝认识的第一天、第一次一起下班、得到每件物件
- 一起吃饭第 1 / 10 / 30 / 50 / 100 / 200 / 365 次，一起下班第 10 / 50 / 100 / 200 次
- 相处一周 / 一个月 / 100 天 / 一年（从认识那天算）

低频展示：有新纪念时首页出现一张卡片，点「收起」后所有当前纪念都算看过，不会连着弹。全部内容在右上角「纪念册」里。首页下方可折叠的「今天的小事」列出今天几点一起上班 / 下班、吃了几顿饭、摸了几次等，没有就写「今天还很安静」，不做每日总结。

老版本升级时会用 SwiftData 日志补算一次（`JisiLog.backfillDiaryIfNeeded`），补出来的纪念只提示最新一条。

## 一键上班

- **Siri / 快捷指令**：App 自带两个快捷指令「带鸡丝上班」「和鸡丝一起下班」（`JisiShortcuts`），可以直接对 Siri 说「带鸡丝上班」，或在快捷指令里调用。
- **控制中心**：iOS 18 起可在控制中心（以及锁屏底部、操作按钮）添加「带鸡丝上班」开关（`JisiWorkControl`），开 = 上班，关 = 一起下班。
- **App 不在前台也能开始实时活动**：这些动作都是 `LiveActivityIntent`，在 App 进程后台执行。SDK 里 `LiveActivityStartingIntent` 自 iOS 17 起废弃并注明改用 `LiveActivityIntent`，所以不需要打开 App。
- **「工作」专注模式自动上班**：设置 > 专注模式 > 工作 > 专注模式过滤条件 > 添加过滤条件 > 鸡丝，打开「自动带鸡丝上班」。专注开启时会自动上班（`JisiFocusFilter`）；专注结束时不会自动下班。
- **到公司自动上班（不在 App 里用定位）**：快捷指令 App > 自动化 > 新建 >「到达」> 选公司地址 > 选「立即运行」> 添加操作「带鸡丝上班」。下班同理用「离开」+「和鸡丝一起下班」。

## 开会模式

首页「我在开会」选 30 / 60 / 90 分钟，锁屏卡片上的「开会」是 60 分钟，也可以对 Siri 说「鸡丝我在开会」。期间鸡丝安静睡觉（摸摸、喂食仍有反应），饭点 / 休息提醒跳过，下班提醒推迟到散会；到点自动恢复，可「提前结束」/「散会」。

为了能跳过开会那一段，饭点 / 休息提醒改为每次排未来 7 天的单次通知（最多 60 条），每次打开 App、点锁屏按钮、开会 / 散会都会重排。很久不打开 App 的话，7 天后提醒会停，打开一次就恢复。

## 已知限制（2026-10-19 iPhone 16 Pro Max / iOS 27 实测）

- 锁屏卡片（Live Activity）上的按钮：手机锁着时点按钮会先要求面容 ID，认证后直接在锁屏执行，不会打开 App。按钮的 intent 已设为 `authenticationPolicy = .alwaysAllowed`（打包后的元数据里确认生效），所以这一步是 iOS 自己要求的。
- 锁屏小组件（accessoryRectangular / accessoryCircular）只能单色显示，用户觉得不好看，已暂时隐藏；代码和单色高对比度头像 `JisiFaceMono.png` 都保留着，在 `LockScreenWidget.swift` 的 `supportedFamilies` 里加回来就能恢复。主屏幕 / 待机用彩色的 systemSmall 小组件。
- 免费开发者账号签的 App 大约 7 天后会过期，需要重新编译安装。
