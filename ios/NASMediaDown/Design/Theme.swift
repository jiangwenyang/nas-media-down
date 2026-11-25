import SwiftUI
import UIKit

/// 应用视觉规范：近黑/近白的极简单色方案，仅保留极淡的状态语义色。
enum Theme {
    // MARK: - 色彩

    /// 唯一的强调色：亮色模式为近黑，深色模式为近白。
    static let ink = dynamic(light: 0x111111, dark: 0xF2F2F2)
    static let inkSoft = dynamic(light: 0x6E6E6E, dark: 0x9A9A9A)
    /// ink 背景上的反色文字。
    static let onInk = dynamic(light: 0xFFFFFF, dark: 0x0C0C0C)

    /// 兼容既有命名。
    static let accent = ink

    /// 低饱和状态色，只用于图标与文字。
    static let success = dynamic(light: 0x4A6B55, dark: 0x9EC0A8)
    static let warning = dynamic(light: 0x7A633B, dark: 0xD3B98C)
    static let danger = dynamic(light: 0x9B4843, dark: 0xE2A09A)

    static let backgroundTop = dynamic(light: 0xFBFBFB, dark: 0x141414)
    static let backgroundBottom = dynamic(light: 0xF1F1F1, dark: 0x090909)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x171717)
    static let muted = dynamic(light: 0xF0F0F0, dark: 0x242424)
    static let hairline = Color.primary.opacity(0.08)

    static let cardRadius: CGFloat = 20

    // MARK: - 渐变

    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [inkSoft, ink],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var progressGradient: LinearGradient {
        LinearGradient(
            colors: [inkSoft, ink],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// 应用背景：纯粹的中性灰渐变。
struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Theme.backgroundTop, Theme.backgroundBottom],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

/// 品牌图标：单色渐变圆角方块 + 下载符号。
struct BrandIcon: View {
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Theme.brandGradient)
            Image(systemName: "arrow.down.to.line")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(Theme.onInk)
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .strokeBorder(Theme.hairline)
        )
        .shadow(color: .black.opacity(0.18), radius: size * 0.18, y: size * 0.07)
    }
}

/// 统一卡片外观。
private struct CardSurface: ViewModifier {
    var padded: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        content
            .padding(padded ? 16 : 0)
            .background(Theme.card, in: shape)
            .overlay(shape.strokeBorder(Theme.hairline))
            .contentShape(shape)
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0 : 0.05),
                radius: 14,
                y: 5
            )
    }
}

extension View {
    /// 卡片外观，内容会被圆角裁切。
    func cardSurface(padded: Bool = true) -> some View {
        modifier(CardSurface(padded: padded))
    }

    /// 页面背景。
    func appBackground() -> some View {
        background(AppBackground())
    }

    /// 主要操作按钮（实心）。
    func primaryAction(fullWidth: Bool = false) -> some View {
        buttonStyle(PrimaryActionButtonStyle(fullWidth: fullWidth))
    }

    /// 次要操作按钮（哑光填充 + 细描边）。
    func secondaryAction(compact: Bool = false) -> some View {
        buttonStyle(SecondaryActionButtonStyle(compact: compact))
    }

    /// 小尺寸行内操作。
    func inlineAction() -> some View {
        buttonStyle(CompactActionButtonStyle())
    }

    /// 极紧凑操作（海报卡片等窄空间）。
    func microAction() -> some View {
        buttonStyle(MicroActionButtonStyle())
    }

    /// 破坏性操作按钮。
    func destructiveAction(compact: Bool = false) -> some View {
        buttonStyle(DestructiveActionButtonStyle(compact: compact))
    }

    /// 圆形主操作（播放按钮等）。
    func circlePrimaryAction() -> some View {
        buttonStyle(CirclePrimaryButtonStyle())
    }
}

/// 实心主按钮。
struct PrimaryActionButtonStyle: ButtonStyle {
    var fullWidth = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.onInk)
            .padding(.horizontal, 18)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(minHeight: 46)
            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(isEnabled ? 1 : 0.35)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .shadow(color: .black.opacity(isEnabled ? 0.12 : 0), radius: 10, y: 5)
    }
}

/// 次要按钮：中性底色与细描边，避免大块彩色胶囊。
struct SecondaryActionButtonStyle: ButtonStyle {
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .caption.weight(.medium) : .subheadline.weight(.medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, compact ? 11 : 15)
            .frame(minHeight: compact ? 32 : 40)
            .background(Theme.muted, in: RoundedRectangle(cornerRadius: compact ? 9 : 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 9 : 12, style: .continuous)
                    .strokeBorder(Theme.hairline)
            )
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// 紧凑行内按钮。
struct CompactActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 10)
            .frame(minHeight: 30)
            .background(Theme.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// 极紧凑按钮：用于海报卡片内的并列操作。
struct MicroActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption2.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 7)
            .frame(minHeight: 30)
            .background(Theme.muted, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// 破坏性操作按钮。
struct DestructiveActionButtonStyle: ButtonStyle {
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .caption.weight(.medium) : .subheadline.weight(.medium))
            .foregroundStyle(Theme.danger)
            .padding(.horizontal, compact ? 11 : 15)
            .frame(minHeight: compact ? 32 : 40)
            .background(Theme.danger.opacity(0.09), in: RoundedRectangle(cornerRadius: compact ? 9 : 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 9 : 12, style: .continuous)
                    .strokeBorder(Theme.danger.opacity(0.16))
            )
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// 圆形主操作按钮。
struct CirclePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.onInk)
            .background(Theme.ink, in: Circle())
            .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.16), radius: 12, y: 6)
            .opacity(isEnabled ? 1 : 0.35)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// 状态标签的配色与图标。
struct StatusStyle {
    let label: String
    let tint: Color
    let symbol: String

    static func job(_ status: JobStatus) -> StatusStyle {
        switch status {
        case .queued: return .init(label: "排队中", tint: .secondary, symbol: "clock.fill")
        case .running: return .init(label: "下载中", tint: Theme.accent, symbol: "arrow.down.circle.fill")
        case .partial: return .init(label: "部分完成", tint: Theme.warning, symbol: "exclamationmark.circle.fill")
        case .completed: return .init(label: "已完成", tint: Theme.success, symbol: "checkmark.circle.fill")
        case .failed: return .init(label: "失败", tint: Theme.danger, symbol: "xmark.circle.fill")
        case .cancelled: return .init(label: "已取消", tint: .secondary, symbol: "slash.circle.fill")
        case .interrupted: return .init(label: "已中断", tint: Theme.warning, symbol: "bolt.slash.fill")
        case .unknown: return .init(label: "未知", tint: .secondary, symbol: "questionmark.circle.fill")
        }
    }

    static func item(_ status: ItemStatus) -> StatusStyle {
        switch status {
        case .pending: return .init(label: "等待中", tint: .secondary, symbol: "clock.fill")
        case .downloading: return .init(label: "下载中", tint: Theme.accent, symbol: "arrow.down.circle.fill")
        case .processing: return .init(label: "合并中", tint: Theme.warning, symbol: "gearshape.fill")
        case .done: return .init(label: "完成", tint: Theme.success, symbol: "checkmark.circle.fill")
        case .failed: return .init(label: "失败", tint: Theme.danger, symbol: "xmark.circle.fill")
        case .cancelled: return .init(label: "已取消", tint: .secondary, symbol: "slash.circle.fill")
        case .unknown: return .init(label: "未知", tint: .secondary, symbol: "questionmark.circle.fill")
        }
    }

    static func episode(_ status: BangumiEpisodeStatus?) -> StatusStyle? {
        switch status {
        case .done: return .init(label: "已完成", tint: Theme.success, symbol: "checkmark.circle.fill")
        case .queued: return .init(label: "排队中", tint: Theme.accent, symbol: "clock.fill")
        case .failed: return .init(label: "失败", tint: Theme.danger, symbol: "xmark.circle.fill")
        case .skipped: return .init(label: "未下载", tint: .secondary, symbol: "minus.circle.fill")
        default: return nil
        }
    }
}
