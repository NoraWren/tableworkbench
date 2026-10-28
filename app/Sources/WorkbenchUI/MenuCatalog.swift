import SwiftUI

/// 菜单栏里一项可点击的条目，标题、快捷键和可用条件都集中写在这里，
/// 菜单视图与断言都读同一份，避免需求写了快捷键而菜单漏挂（R-SHELL-02）。
public struct MenuItem: Equatable, Identifiable {
    /// 菜单里的定位标识，断言用它区分每一项。
    public enum ID: String, CaseIterable {
        case openFile
        case exportFile
        case closeFile
        case runSQL
        case cancelSQL
        case newQuery
        case autoAnalysis
        case toggleSidebar
        case toggleInspector
        case toggleSQL
        case findFilter
    }

    /// 快捷键的修饰键集合，避开 SwiftUI 的 EventModifiers 便于断言。
    public enum Modifier: String, CaseIterable {
        case command
        case shift
        case option
        case control

        var eventModifiers: EventModifiers {
            switch self {
            case .command: return .command
            case .shift: return .shift
            case .option: return .option
            case .control: return .control
            }
        }

        /// 用在断言与文档里的写法，比如 shift+command。
        var symbol: String { rawValue }

        var titlePrefix: String {
            switch self {
            case .command: return "⌘"
            case .shift: return "⇧"
            case .option: return "⌥"
            case .control: return "⌃"
            }
        }
    }

    /// 没有快捷键的菜单项用 nil，keys 只放快捷键字符。
    public let id: ID
    public let title: String
    public let key: Character
    public let modifiers: [Modifier]

    public init(_ id: ID, title: String, key: Character, modifiers: [Modifier]) {
        self.id = id
        self.title = title
        self.key = key
        self.modifiers = modifiers
    }

    public var keyboardShortcut: KeyboardShortcut {
        KeyboardShortcut(KeyEquivalent(key), modifiers: eventModifiers)
    }

    /// 靠修饰键顺序稳定下来，用于查重。
    public var combination: String {
        let sorted = modifiers.map(\.symbol).sorted().joined(separator: "+")
        return sorted.isEmpty ? String(key) : "\(sorted)+\(key)"
    }

    /// 给人看的组合，比如 ⇧⌘E。
    public var displayShortcut: String {
        let ordered: [Modifier] = [.control, .option, .shift, .command]
        return modifiers
            .sorted { (ordered.firstIndex(of: $0) ?? 0) < (ordered.firstIndex(of: $1) ?? 0) }
            .map(\.titlePrefix)
            .joined() + String(key).uppercased()
    }

    private var eventModifiers: EventModifiers {
        modifiers.reduce(EventModifiers()) { $0.union($1.eventModifiers) }
    }
}

/// 菜单项清单，按菜单分组。
public enum MenuCatalog {
    public static let file: [MenuItem] = [
        MenuItem(.openFile, title: "打开文件…", key: "o", modifiers: [.command]),
        MenuItem(.exportFile, title: "导出…", key: "e", modifiers: [.shift, .command]),
        MenuItem(.closeFile, title: "关闭文件", key: "w", modifiers: [.shift, .command])
    ]

    public static let query: [MenuItem] = [
        MenuItem(.runSQL, title: "运行", key: "r", modifiers: [.command]),
        MenuItem(.cancelSQL, title: "取消", key: ".", modifiers: [.command]),
        MenuItem(.newQuery, title: "新建查询", key: "n", modifiers: [.command]),
        MenuItem(.autoAnalysis, title: "一键分析", key: "a", modifiers: [.shift, .command])
    ]

    /// 视图菜单的标题随开关状态变化，这里的 title 是打开状态时的写法。
    public static let view: [MenuItem] = [
        MenuItem(.toggleSidebar, title: "隐藏侧栏", key: "s", modifiers: [.control, .command]),
        MenuItem(.toggleInspector, title: "隐藏检查器", key: "i", modifiers: [.command, .option]),
        MenuItem(.toggleSQL, title: "隐藏 SQL 抽屉", key: "j", modifiers: [.command]),
        MenuItem(.findFilter, title: "查找…", key: "f", modifiers: [.command])
    ]

    public static let all: [MenuItem] = file + query + view

    /// 同一组合挂了两次，系统会静默丢掉其中一个，所以启动前就该查出来。
    public static var duplicatedCombinations: [String] {
        var seen = Set<String>()
        var duplicated = Set<String>()
        for item in all {
            if !seen.insert(item.combination).inserted {
                duplicated.insert(item.combination)
            }
        }
        return duplicated.sorted()
    }

    /// 视图菜单里开关类条目的两种标题。
    public static func viewTitle(_ id: MenuItem.ID, isOn: Bool) -> String {
        switch id {
        case .toggleSidebar: return isOn ? "隐藏侧栏" : "显示侧栏"
        case .toggleInspector: return isOn ? "隐藏检查器" : "显示检查器"
        case .toggleSQL: return isOn ? "隐藏 SQL 抽屉" : "显示 SQL 抽屉"
        default: return all.first { $0.id == id }?.title ?? ""
        }
    }

    public static func item(_ id: MenuItem.ID) -> MenuItem? {
        all.first { $0.id == id }
    }

    /// 状态下这些条目是否可点，菜单视图直接查表。
    public static func isEnabled(_ id: MenuItem.ID, hasFile: Bool, canExport: Bool, canRunSQL: Bool, canAnalyze: Bool, canCancel: Bool) -> Bool {
        switch id {
        case .openFile, .toggleSidebar, .toggleInspector, .toggleSQL: return true
        case .cancelSQL: return canCancel
        case .exportFile: return canExport
        case .closeFile, .newQuery, .findFilter: return hasFile
        case .runSQL: return canRunSQL
        case .autoAnalysis: return canAnalyze
        }
    }
}

