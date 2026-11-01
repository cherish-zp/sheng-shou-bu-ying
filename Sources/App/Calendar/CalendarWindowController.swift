import AppKit

/// 轻量日历窗口：当月网格深色视图（对标浮引轻量日历）。
final class CalendarWindowController: NSObject {
    let window: NSWindow
    private var monthLabel: NSTextField!
    private var gridLabel: NSTextField!
    private var current: (year: Int, month: Int) = {
        let now = Calendar.current.dateComponents([.year, .month], from: Date())
        return (now.year ?? 2026, now.month ?? 1)
    }()

    override init() {
        let calendar = Calendar.current
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300),
                          styleMask: [.titled, .closable],
                          backing: .buffered, defer: false)
        super.init()
        window.title = "日历"
        window.isReleasedWhenClosed = false
        window.center()
        window.backgroundColor = UITheme.panelBackground
        window.appearance = NSAppearance(named: .darkAqua)

        let content = NSView(frame: window.contentView!.frame)
        content.autoresizingMask = [.width, .height]
        window.contentView = content

        monthLabel = NSTextField(labelWithString: "")
        monthLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        monthLabel.textColor = UITheme.textPrimary
        monthLabel.alignment = .center
        monthLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(monthLabel)

        gridLabel = NSTextField(labelWithString: "")
        gridLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        gridLabel.textColor = UITheme.textPrimary
        gridLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(gridLabel)

        let prev = NSButton(title: "‹", target: self, action: #selector(prevMonth))
        let next = NSButton(title: "›", target: self, action: #selector(nextMonth))
        for btn in [prev, next] {
            btn.bezelStyle = .rounded
            btn.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(btn)
        }

        NSLayoutConstraint.activate([
            monthLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            monthLabel.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            prev.centerYAnchor.constraint(equalTo: monthLabel.centerYAnchor),
            prev.trailingAnchor.constraint(equalTo: monthLabel.leadingAnchor, constant: -16),
            next.centerYAnchor.constraint(equalTo: monthLabel.centerYAnchor),
            next.leadingAnchor.constraint(equalTo: monthLabel.trailingAnchor, constant: 16),
            gridLabel.topAnchor.constraint(equalTo: monthLabel.bottomAnchor, constant: 10),
            gridLabel.centerXAnchor.constraint(equalTo: content.centerXAnchor),
        ])
        render()
    }

    func showPanel() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func prevMonth() {
        current.month -= 1
        if current.month == 0 { current.month = 12; current.year -= 1 }
        render()
    }

    @objc private func nextMonth() {
        current.month += 1
        if current.month == 13 { current.month = 1; current.year += 1 }
        render()
    }

    private func render() {
        monthLabel.stringValue = "\(current.year) 年 \(current.month) 月"
        let grid = CalendarGrid.monthGrid(year: current.year, month: current.month)
        let today = Calendar.current.component(.day, from: Date())
        let isThisMonth = current.month == Calendar.current.component(.month, from: Date())
            && current.year == Calendar.current.component(.year, from: Date())
        var lines = ["一  二  三  四  五  六  日"]
        for row in grid {
            var line = ""
            for cell in row {
                if let day = cell {
                    let mark = (day == today && isThisMonth) ? "*" : " "
                    line += String(format: "%2d%@ ", day, mark)
                } else {
                    line += "    "
                }
            }
            lines.append(line)
        }
        gridLabel.stringValue = lines.joined(separator: "\n")
    }
}
