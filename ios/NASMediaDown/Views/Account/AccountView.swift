import SwiftUI

/// 账号页：服务器连接、哔哩哔哩登录与本地会话。
struct AccountView: View {
    @Environment(AppState.self) private var app

    @State private var status: BilibiliStatus?
    @State private var loading = true
    @State private var error: String?
    @State private var showQRLogin = false
    @State private var bilibiliBusy = false
    @State private var confirmServerLogout = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("管理服务器连接与哔哩哔哩登录状态。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    serverCard
                    bilibiliCard
                    sessionCard
                    securityNote
                    versionFooter
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 36)
            }
            .appBackground()
            .navigationTitle("账号")
            .navigationBarTitleDisplayMode(.large)
            .refreshable { await loadStatus() }
            .task { await loadStatus() }
            .sheet(isPresented: $showQRLogin) {
                QRLoginView {
                    await loadStatus()
                    app.showToast("哔哩哔哩登录成功", style: .success)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .confirmationDialog(
                "退出登录",
                isPresented: $confirmServerLogout,
                titleVisibility: .visible
            ) {
                Button("退出登录", role: .destructive) {
                    Task { await app.logout() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("退出后需要重新输入访问密码，已保存的服务器地址会保留。")
            }
        }
    }

    // MARK: - 服务器

    private var serverCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                Image(systemName: "externaldrive.connected.to.line.below")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Text("服务器")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                StatusBadge(text: "已连接", tint: Theme.success, showDot: true)
            }

            HStack(spacing: 12) {
                iconTile("server.rack", tint: Theme.accent, size: 46)

                VStack(alignment: .leading, spacing: 3) {
                    Text(app.selectedServer?.name ?? "未选择服务器")
                        .font(.headline)
                        .lineLimit(1)
                    if let address = app.selectedServer?.address,
                       address != app.selectedServer?.name {
                        Text(address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Button {
                    app.switchServer()
                } label: {
                    Label("切换", systemImage: "arrow.left.arrow.right")
                }
                .secondaryAction(compact: true)
            }

            Divider()
                .overlay(Theme.hairline)

            HStack(spacing: 18) {
                metric(label: "服务版本", value: app.currentVersion ?? "—")
                Rectangle()
                    .fill(Theme.hairline)
                    .frame(width: 1, height: 24)
                metric(label: "会话状态", value: "已登录")
                Spacer(minLength: 0)
            }
        }
        .cardSurface()
    }

    // MARK: - 哔哩哔哩

    private var bilibiliCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                Image(systemName: "play.tv")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Text("哔哩哔哩")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                bilibiliStatusBadge
            }

            if loading && status == nil {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在读取登录状态…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            } else if let status, status.loggedIn {
                HStack(spacing: 12) {
                    bilibiliMark(size: 46)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(status.uname ?? "已保存登录信息")
                            .font(.headline)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            if status.vip {
                                vipTag
                            }
                            if let expires = status.expiresAt {
                                Text("有效期至 \(Format.date(expires))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Spacer(minLength: 4)
                }

                Divider()
                    .overlay(Theme.hairline)

                HStack(spacing: 10) {
                    Button {
                        Task { await loadStatus() }
                    } label: {
                        Label("刷新状态", systemImage: "arrow.clockwise")
                    }
                    .secondaryAction(compact: true)
                    .disabled(bilibiliBusy || loading)

                    Spacer(minLength: 0)

                    Button {
                        logoutBilibili()
                    } label: {
                        Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .destructiveAction(compact: true)
                    .disabled(bilibiliBusy)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    bilibiliMark(size: 46)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("未登录")
                            .font(.headline)
                        Text("扫码登录后可下载大会员清晰度，并读取关注列表用于追番。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Button {
                    showQRLogin = true
                } label: {
                    Label("扫码登录", systemImage: "qrcode")
                }
                .primaryAction(fullWidth: true)
            }

            if let error {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                    Text(error)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button("重试") {
                        Task { await loadStatus() }
                    }
                    .inlineAction()
                }
                .foregroundStyle(Theme.danger)
            }
        }
        .cardSurface()
    }

    @ViewBuilder
    private var bilibiliStatusBadge: some View {
        if loading && status == nil {
            ProgressView()
                .controlSize(.mini)
        } else if let status, status.loggedIn {
            StatusBadge(text: "已登录", tint: Theme.success, showDot: true)
        } else {
            StatusBadge(text: "未登录", tint: .secondary)
        }
    }

    // MARK: - 会话与说明

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "lock.rectangle.stack")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Text("本地会话")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Button {
                confirmServerLogout = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.footnote.weight(.semibold))
                    Text("退出登录")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(Theme.danger)
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text("退出后需要重新输入访问密码，已保存的服务器地址会保留。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .cardSurface()
    }

    private var securityNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.footnote)
                .foregroundStyle(Theme.accent)
            Text("访问密码只用于登录 NAS，不会保存在设备上；哔哩哔哩 Cookie 仅保存在 NAS 本地。会员内容请遵守哔哩哔哩服务条款。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    private var versionFooter: some View {
        HStack {
            Text("媒体下载 · iOS 1.0")
            Spacer()
            if let version = app.currentVersion {
                Text("服务 \(version)")
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 4)
    }

    // MARK: - 小组件

    private func iconTile(_ symbol: String, tint: Color, size: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                Color.primary.opacity(0.05),
                in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            )
    }

    private func metric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.footnote.weight(.medium))
        }
    }

    private func bilibiliMark(size: CGFloat) -> some View {
        Text("B")
            .font(.system(size: size * 0.5, weight: .black, design: .rounded))
            .foregroundStyle(Theme.onInk)
            .frame(width: size, height: size)
            .background(
                Theme.ink,
                in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .strokeBorder(Theme.hairline)
            )
    }

    private var vipTag: some View {
        HStack(spacing: 3) {
            Image(systemName: "crown.fill")
                .font(.system(size: 9, weight: .semibold))
            Text("大会员")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Color.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.12), in: Capsule())
    }

    // MARK: - 数据

    private func loadStatus() async {
        if status == nil {
            loading = true
        }
        do {
            let api = try app.requireAPI()
            status = try await api.bilibiliStatus()
            error = nil
        } catch {
            self.error = APIError.describe(error)
        }
        loading = false
    }

    private func logoutBilibili() {
        guard !bilibiliBusy else { return }
        bilibiliBusy = true
        Task {
            do {
                let api = try app.requireAPI()
                try await api.bilibiliLogout()
                status = BilibiliStatus(loggedIn: false, uname: nil, vip: false, expiresAt: nil)
                app.showToast("已退出哔哩哔哩登录", style: .info)
            } catch {
                app.showToast(APIError.describe(error), style: .error)
            }
            bilibiliBusy = false
        }
    }
}
