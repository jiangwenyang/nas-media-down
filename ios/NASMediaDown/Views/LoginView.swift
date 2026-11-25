import SwiftUI

/// 访问密码登录页。
struct LoginView: View {
    @Environment(AppState.self) private var app

    @State private var password = ""
    @State private var revealPassword = false
    @State private var submitting = false
    @State private var error: String?

    @FocusState private var passwordFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 48)

                BrandIcon(size: 78)

                VStack(spacing: 6) {
                    Text("媒体下载")
                        .font(.largeTitle.weight(.bold))
                    Text("登录后即可探测并下载视频")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let server = app.selectedServer {
                    serverChip(server)
                }

                VStack(spacing: 14) {
                    passwordField

                    if let error {
                        ErrorNotice(text: error)
                    }

                    Button(action: submit) {
                        HStack(spacing: 8) {
                            if submitting {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(Theme.onInk)
                            }
                            Text(submitting ? "正在验证…" : "进入控制台")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .primaryAction()
                    .disabled(submitting || password.isEmpty)
                }
                .padding(18)
                .cardSurface(padded: false)

                Text("访问密码由 NAS 上的环境变量 ACCESS_PASSWORD 配置")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)

                Spacer(minLength: 48)
            }
            .padding(.horizontal, 22)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .appBackground()
        .onAppear { passwordFocused = true }
    }

    private var passwordField: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Group {
                if revealPassword {
                    TextField("访问密码", text: $password)
                } else {
                    SecureField("访问密码", text: $password)
                }
            }
            .textContentType(.password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.go)
            .focused($passwordFocused)
            .onSubmit(submit)

            Button {
                revealPassword.toggle()
            } label: {
                Image(systemName: revealPassword ? "eye.slash" : "eye")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(revealPassword ? "隐藏密码" : "显示密码")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            Theme.muted,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(passwordFocused ? Theme.ink.opacity(0.35) : .clear, lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.15), value: passwordFocused)
    }

    private func serverChip(_ server: Server) -> some View {
        Button {
            app.switchServer()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "externaldrive.connected.to.line.below")
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(server.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(server.address)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                Text("切换")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.accent)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemGroupedBackground), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06)))
            .frame(maxWidth: 320)
        }
        .buttonStyle(.plain)
    }

    private func submit() {
        let value = password
        guard !value.isEmpty, !submitting else { return }
        submitting = true
        error = nil
        Task {
            do {
                try await app.login(password: value)
            } catch {
                self.error = APIError.describe(error)
                password = ""
                passwordFocused = true
            }
            submitting = false
        }
    }
}
