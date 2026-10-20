import JisiWatchKit
import SwiftUI
import UserNotifications
import WatchKit

/// 久坐提醒展开后的样子：鸡丝 + 一句话，下面是系统放的「站起来了」按钮。
final class StandNotificationController: WKUserNotificationHostingController<StandNotificationView> {
    private var text = StandPlan.body(interval: StandPlan.defaultInterval)

    override var body: StandNotificationView { StandNotificationView(text: text) }

    override func didReceive(_ notification: UNNotification) {
        text = notification.request.content.body
    }
}

struct StandNotificationView: View {
    var text: String

    var body: some View {
        VStack(spacing: 6) {
            WatchCatFace(expression: .curious)
                .frame(width: 72, height: 72)
            Text(text)
                .font(.body)
                .multilineTextAlignment(.center)
        }
    }
}
