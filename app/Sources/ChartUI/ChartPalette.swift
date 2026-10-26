import AppKit

/// 图表配色的对比度兜底。
///
/// 设计上柱、线、饼跟随系统强调色，文字用次要色。问题是系统强调色是按浅色底挑的，
/// 压到深色底上、或者叠一层半透明跟底混过之后，对比度会掉到门槛以下。
/// 实测（截图是 Display P3，按 sRGB 换算后）：深色底上 accent@0.85 是 2.78:1，
/// 浅色底上系统次要文字是 3.84:1，都够不上 4.5:1。
///
/// 这里的做法是保色相、沿明度往背景反方向推，推到够对比度为止。所有颜色都做成
/// 动态色，切换深浅色时按当下外观重新解析，不缓存旧外观的结果。
public enum ChartPalette {
    /// 次级图形（“其他”那根柱、饼图隔行扇区）要达到的对比度。R-VIZ-04 要求不低于 4.5:1，
    /// 比 WCAG 2.2 对非文字元素的 3:1 更严。
    ///
    /// 目标值取 4.6 而不是 4.5：位图落在 Display P3 上，转回 sRGB 量的时候会有
    /// 零点几的取整误差，按 4.5 卡边量出来是 4.48，留一点余量才稳。
    public static let figureContrast: Double = 4.6
    /// 主图形（柱子、折线、饼图奇数扇区）的对比度。
    ///
    /// 推值只沿明度轴走，所以两个目标值一样时，主色和次级色会落到同一个亮度上——实测
    /// 两者之间只有 1.00:1，饼图上相邻扇区在灰度下根本分不开。主色单独深一档，留出
    /// 明度差，色弱用户和黑白打印也看得出是两块。
    public static let primaryContrast: Double = 6.6
    /// 图上 8–10 点的小字，AA 的门槛是 4.5:1。
    public static let textContrast: Double = 4.6
    /// 网格线只表示刻度位置，属装饰，压到刚好看得出来就行。
    public static let gridContrast: Double = 1.35

    /// 主填色：柱子、折线、饼图隔行的第一色。
    public static func fill(background: NSColor? = nil) -> NSColor {
        dynamic(background) { base in
            adjusted(NSColor.controlAccentColor, against: base, minContrast: primaryContrast)
        }
    }

    /// 次级填色：给“其他”和饼图隔行用，同色相但明度退一截，仍要够对比度。
    public static func softFill(background: NSColor? = nil) -> NSColor {
        dynamic(background) { base in
            let muted = blend(NSColor.controlAccentColor, toward: base, ratio: 0.45)
            return adjusted(muted, against: base, minContrast: figureContrast)
        }
    }

    /// 坐标刻度、组名、数值标注的文字色。
    public static func text(background: NSColor? = nil) -> NSColor {
        dynamic(background) { base in
            let flat = flatten(NSColor.secondaryLabelColor, over: base)
            return adjusted(flat, against: base, minContrast: textContrast)
        }
    }

    /// 网格线。不跟柱子和文字抢注意力，只保证看得出格位。
    public static func grid(background: NSColor? = nil) -> NSColor {
        dynamic(background) { base in
            let flat = flatten(NSColor.separatorColor, over: base)
            return adjusted(flat, against: base, minContrast: gridContrast)
        }
    }

    /// 当前外观下图表实际画在上面的底色。离屏渲染和真实窗口都走这一条，量出来的值才对得上。
    public static func drawingBackground() -> NSColor {
        canvas
    }

    /// 图表画布色。
    ///
    /// 之前这里取的是系统 controlBackgroundColor，但离屏渲染出来的实际底色根本对不上
    /// （浅色取到 255,255,255，画出来是 236,236,236），对比度算得再准也是空算。
    /// 现在画布色由 ChartView 自己铺，取色和渲染用同一个值，量出来的数才可信。
    public static let canvas: NSColor = NSColor(name: nil) { appearance in
        var resolved = NSColor(srgbRed: 0.925, green: 0.925, blue: 0.925, alpha: 1)
        appearance.performAsCurrentDrawingAppearance {
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            resolved = dark
                ? NSColor(srgbRed: 0.196, green: 0.196, blue: 0.196, alpha: 1)
                : NSColor(srgbRed: 0.925, green: 0.925, blue: 0.925, alpha: 1)
        }
        return resolved
    }

    /// 颜色要等到真正画的时候才按当前外观解析，否则在浅色窗口里建好的图切到深色不跟着变。
    static func dynamic(_ background: NSColor?, _ resolve: @escaping (NSColor) -> NSColor) -> NSColor {
        // 显式给了底色（离屏渲染量对比度用）就按它算，不看外观。
        if let background { return resolve(background.usingColorSpace(.sRGB) ?? background) }
        return NSColor(name: nil) { appearance in
            var resolved = NSColor.labelColor
            appearance.performAsCurrentDrawingAppearance {
                resolved = resolve(drawingBackground())
            }
            return resolved
        }
    }

    /// 保色相、只在明度轴上走，直到与底色的对比度达到 minContrast。
    public static func adjusted(_ color: NSColor, against background: NSColor, minContrast: Double) -> NSColor {
        let base = background.usingColorSpace(.sRGB) ?? NSColor.white
        let start = color.usingColorSpace(.sRGB) ?? NSColor.systemBlue
        if contrast(start, base) >= minContrast { return start }

        // 底色暗就往白推，底色亮就往黑推，这样对比度单调上升，二分能收敛。
        let toward: NSColor = luminance(base) < 0.5 ? .white : .black
        var low = 0.0
        var high = 1.0
        var best = start
        for _ in 0..<20 {
            let ratio = (low + high) / 2
            let candidate = blend(start, toward: toward, ratio: ratio)
            if contrast(candidate, base) >= minContrast {
                best = candidate
                high = ratio
            } else {
                low = ratio
            }
        }
        return best
    }

    /// 把 fg 按比例混进 toward，比例越大越接近 toward。
    static func blend(_ fg: NSColor, toward: NSColor, ratio: Double) -> NSColor {
        let a = fg.usingColorSpace(.sRGB) ?? fg
        let b = toward.usingColorSpace(.sRGB) ?? toward
        let t = min(1, max(0, ratio))
        return NSColor(
            srgbRed: a.redComponent + (b.redComponent - a.redComponent) * t,
            green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
            blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t,
            alpha: 1
        )
    }

    /// 半透明色先按底色合成成实色，否则算出来的对比度是假的。
    public static func flatten(_ color: NSColor, over base: NSColor) -> NSColor {
        let fg = color.usingColorSpace(.sRGB) ?? color
        let bg = base.usingColorSpace(.sRGB) ?? base
        let a = fg.alphaComponent
        return NSColor(
            srgbRed: fg.redComponent * a + bg.redComponent * (1 - a),
            green: fg.greenComponent * a + bg.greenComponent * (1 - a),
            blue: fg.blueComponent * a + bg.blueComponent * (1 - a),
            alpha: 1
        )
    }

    /// WCAG 相对亮度。
    public static func luminance(_ color: NSColor) -> Double {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        func channel(_ value: CGFloat) -> Double {
            let v = Double(value)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(srgb.redComponent)
            + 0.7152 * channel(srgb.greenComponent)
            + 0.0722 * channel(srgb.blueComponent)
    }

    /// WCAG 对比度，1:1 到 21:1。
    public static func contrast(_ a: NSColor, _ b: NSColor) -> Double {
        let la = luminance(a)
        let lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
