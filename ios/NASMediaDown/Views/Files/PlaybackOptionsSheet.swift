import SwiftUI
import UIKit

/// 把文件的短期链接交给外部播放器，无需下载。
struct PlaybackOptionsSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    let link: PlaybackLink

    @State private var shareItem: ShareItem?
    @State private var copied = false

    private var players: [ExternalPlayer.Option] {
        ExternalPlayer.options(for: link.url)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .overlay(Theme.hairline)

            ScrollView {
                VStack(spacing: 12) {
                    if players.isEmpty {
                        hint
                    }

                    optionsCard
                }
                .padding(16)
            }

            footer
        }
        .appBackground()
        .presentationDetents([.height(players.isEmpty ? 420 : 520), .large])
        .presentationDragIndicator(.visible)
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
                .presentationDetents([.medium, .large])
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: "play.rectangle.on.rectangle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text("用外部播放器打开")
                    .font(.headline)
                Spacer()
            }
            Text(link.filename)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("链接有效期至 \(Format.date(link.expiresAt))，无需下载。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private var hint: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("未检测到 Infuse 或 VLC。可安装后重试，或使用分享、浏览器打开链接。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.muted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var optionsCard: some View {
        VStack(spacing: 0) {
            ForEach(players) { player in
                optionRow(
                    icon: player.systemImage,
                    title: player.title,
                    subtitle: player.subtitle
                ) {
                    ExternalPlayer.open(player.url)
                    dismiss()
                }
                rowDivider
            }

            optionRow(
                icon: "square.and.arrow.up",
                title: "分享链接",
                subtitle: "发送到其他 App 或设备"
            ) {
                shareItem = ShareItem(url: link.url)
            }
            rowDivider

            optionRow(
                icon: "safari",
                title: "在浏览器中打开",
                subtitle: "使用系统浏览器播放或保存"
            ) {
                ExternalPlayer.open(link.url)
                dismiss()
            }
            rowDivider

            optionRow(
                icon: copied ? "checkmark" : "doc.on.doc",
                title: copied ? "链接已复制" : "复制链接",
                subtitle: "6 小时内可访问"
            ) {
                UIPasteboard.general.string = link.url.absoluteString
                copied = true
                app.showToast("链接已复制", style: .success)
            }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.hairline)
        )
    }

    private var rowDivider: some View {
        Divider()
            .overlay(Theme.hairline)
            .padding(.leading, 58)
    }

    private func optionRow(
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 32, height: 32)
                    .background(
                        Color.primary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        Text("任何获得链接的人都能访问该文件，请勿公开分享。")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
    }
}
