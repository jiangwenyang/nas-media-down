import SwiftUI

/// 状态胶囊标签。
struct StatusBadge: View {
    let text: String
    let tint: Color
    var showDot = false

    var body: some View {
        HStack(spacing: 5) {
            if showDot {
                Circle()
                    .fill(tint)
                    .frame(width: 5, height: 5)
            }
            Text(text)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.05), in: Capsule())
    }
}

/// 渐变进度条。
struct ProgressTrack: View {
    let progress: Double
    var active = false
    var height: CGFloat = 6

    private var clamped: Double { min(1, max(0, progress)) }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(Theme.progressGradient)
                    .frame(width: proxy.size.width * clamped)
                    .animation(.easeOut(duration: 0.35), value: clamped)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("进度")
        .accessibilityValue(Format.percent(clamped))
    }
}

/// 网络图片占位与加载。
struct RemoteImage: View {
    let urlString: String?
    var symbol = "film"

    var body: some View {
        AsyncImage(url: urlString.flatMap(URL.init(string:))) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                placeholder
            case .empty:
                ZStack {
                    placeholder
                    ProgressView()
                        .controlSize(.small)
                }
            @unknown default:
                placeholder
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            Color(.tertiarySystemGroupedBackground)
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tertiary)
        }
    }
}

/// 错误提示条。
struct ErrorNotice: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote)
            Text(text)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.danger)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.danger.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// 图标徽章。
struct IconBadge: View {
    let systemName: String
    var tint: Color = Theme.accent
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                Color.primary.opacity(0.05),
                in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            )
    }
}

/// 区块标题。
struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
        }
    }
}

/// 空状态卡片。
struct EmptyStateCard: View {
    let icon: String
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline.weight(.medium))
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .secondaryAction()
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .cardSurface(padded: false)
    }
}

/// 顶部轻提示。
struct ToastOverlay: View {
    let toast: ToastMessage?

    var body: some View {
        if let toast {
            HStack(spacing: 8) {
                Image(systemName: icon(for: toast.style))
                    .foregroundStyle(tint(for: toast.style))
                Text(toast.text)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .transition(.move(edge: .top).combined(with: .opacity))
            .id(toast.id)
        }
    }

    private func icon(for style: ToastMessage.Style) -> String {
        switch style {
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func tint(for style: ToastMessage.Style) -> Color {
        switch style {
        case .success: return Theme.success
        case .error: return Theme.danger
        case .info: return Theme.accent
        }
    }
}

/// 单视频 / 播放列表卡片上的时长角标。
struct DurationBadge: View {
    let seconds: Double?

    var body: some View {
        Text(Format.duration(seconds))
            .font(.caption2.weight(.medium).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}
