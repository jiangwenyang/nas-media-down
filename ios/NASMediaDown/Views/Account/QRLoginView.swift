import SwiftUI

/// 哔哩哔哩扫码登录。
struct QRLoginView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    /// 登录成功后回调（由父视图刷新状态与提示）。
    let onSuccess: () async -> Void

    @State private var qrImage: UIImage?
    @State private var key: String?
    @State private var hint = "正在生成二维码…"
    @State private var error: String?
    @State private var loading = true
    @State private var expired = false
    @State private var scanned = false

    @State private var pollTask: Task<Void, Never>?
    @State private var generation = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    qrCard

                    HStack(spacing: 6) {
                        if scanned {
                            Image(systemName: "iphone.radiowaves.left.and.right")
                                .foregroundStyle(Theme.accent)
                        }
                        Text(hint)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                    .multilineTextAlignment(.center)

                    if let error {
                        ErrorNotice(text: error)
                    }

                    if expired || error != nil {
                        Button {
                            Task { await generate() }
                        } label: {
                            Label("重新获取二维码", systemImage: "arrow.clockwise")
                        }
                        .secondaryAction()
                        .disabled(loading)
                    }

                    Text("扫码后请在手机上确认登录，二维码几分钟内有效。登录 Cookie 仅保存在 NAS 上。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
                .padding(20)
            }
            .appBackground()
            .navigationTitle("哔哩哔哩登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task { await generate() }
            .onDisappear {
                generation += 1
                pollTask?.cancel()
                pollTask = nil
            }
        }
    }

    private var qrCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.white)
                .shadow(color: .black.opacity(0.12), radius: 20, y: 8)

            if loading {
                ProgressView()
                    .controlSize(.large)
                    .tint(.gray)
            } else if expired {
                VStack(spacing: 8) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)
                    Text("二维码已过期")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if let qrImage {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(18)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)
                    Text("二维码不可用")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 280, height: 280)
        .accessibilityLabel("哔哩哔哩登录二维码")
    }

    // MARK: - 生成与轮询

    private func generate() async {
        generation += 1
        let current = generation
        pollTask?.cancel()
        pollTask = nil

        loading = true
        error = nil
        expired = false
        scanned = false
        qrImage = nil
        hint = "正在生成二维码…"

        do {
            let api = try app.requireAPI()
            let code = try await api.bilibiliQRCode()
            guard current == generation else { return }

            key = code.key
            qrImage = QRCodeRenderer.image(for: code.url)
            loading = false
            hint = "请使用哔哩哔哩 App 扫码"
            startPolling(generation: current)
        } catch {
            guard current == generation else { return }
            self.error = APIError.describe(error)
            loading = false
        }
    }

    private func startPolling(generation current: Int) {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if Task.isCancelled { return }
                guard current == generation, let key else { return }

                do {
                    let api = try app.requireAPI()
                    let poll = try await api.bilibiliPoll(key: key)
                    guard current == generation else { return }

                    if poll.code == 0 {
                        hint = "登录成功"
                        dismiss()
                        await onSuccess()
                        return
                    }
                    if poll.code == 86038 {
                        expired = true
                        hint = "二维码已过期"
                        return
                    }
                    scanned = poll.code == 86090
                    hint = poll.status
                } catch {
                    guard current == generation else { return }
                    self.error = APIError.describe(error)
                    return
                }
            }
        }
    }
}
