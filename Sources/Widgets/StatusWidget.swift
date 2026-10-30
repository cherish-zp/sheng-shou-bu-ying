import WidgetKit
import SwiftUI

/// 桌面小组件（最小实现）：显示应用名与当前日期。
/// 完整数据联动需 App Group（后续批次）；本批先交付可编译的静态小组件骨架。
@main
struct ShouShouWidgetBundle: WidgetBundle {
    var body: some Widget {
        ShouShouStatusWidget()
    }
}

struct ShouShouStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ShouShouStatus", provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
        }
        .configurationDisplayName("圣手捕影")
        .description(Text("查看圣手捕影状态"))
        .supportedFamilies([.systemSmall])
    }
}

struct StatusEntry: TimelineEntry {
    let date: Date
}

struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry { StatusEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        completion(StatusEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        completion(Timeline(entries: [StatusEntry(date: Date())], policy: .atEnd))
    }
}

struct StatusWidgetView: View {
    let entry: StatusEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("圣手捕影")
                .font(.system(size: 13, weight: .semibold))
            Text("运行中 · \(entry.date.formatted(date: .numeric, time: .shortened))")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(12)
    }
}
