import JisiKit
import SwiftUI
import UniformTypeIdentifiers

/// 设置里的「备份」：导出到「文件」App / 从文件导入（先确认会覆盖）。
struct BackupSection: View {
    @Environment(HomeModel.self) private var model
    @State private var importing = false
    @State private var pending: JisiBackup?
    @State private var message: String?
    @State private var exportURL: URL?

    var body: some View {
        Section {
            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("导出备份", systemImage: "square.and.arrow.up")
                }
            } else {
                Label("导出备份", systemImage: "square.and.arrow.up").foregroundStyle(.secondary)
            }
            Button {
                importing = true
            } label: {
                Label("导入备份", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("备份")
        } footer: {
            Text("导出的文件包含作息、提醒设置、鸡丝的物件、回忆和全部互动记录。可以选「存储到文件」。")
        }
        // 打开设置时生成最新的备份文件（很小），点「导出」直接分享这个文件。
        .task { exportURL = try? Self.writeBackupFile() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let ok = url.startAccessingSecurityScopedResource()
                defer { if ok { url.stopAccessingSecurityScopedResource() } }
                pending = try JisiBackup.decode(Data(contentsOf: url))
            } catch {
                message = (error as? LocalizedError)?.errorDescription ?? "读不了这个文件：\(error.localizedDescription)"
            }
        }
        .alert("导入这个备份？", isPresented: .constant(pending != nil), presenting: pending) { backup in
            Button("导入并覆盖", role: .destructive) {
                model.restore(backup)
                pending = nil
                message = "导入好了。"
            }
            Button("取消", role: .cancel) { pending = nil }
        } message: { backup in
            Text("备份时间 \(backup.exportedAt.formatted(date: .abbreviated, time: .shortened))，共 \(backup.log.count) 条记录、\(backup.diary.memories.count) 条回忆。\n现在手机上的鸡丝数据会被它覆盖。")
        }
        .alert(message ?? "", isPresented: .constant(message != nil)) {
            Button("好") { message = nil }
        }
    }
}

extension BackupSection {
    @MainActor
    static func writeBackupFile() throws -> URL {
        let data = try SharedStore.shared.makeBackup(log: JisiLog.allRecords()).encoded()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("backup", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(JisiBackup.fileName())
        try data.write(to: url, options: .atomic)
        return url
    }
}
