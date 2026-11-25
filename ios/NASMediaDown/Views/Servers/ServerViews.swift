import SwiftUI

/// 服务器选择与管理。
struct ServerListView: View {
    @Environment(AppState.self) private var app
    @State private var showAdd = false
    @State private var deleteTarget: Server?

    var body: some View {
        NavigationStack {
            Group {
                if app.servers.isEmpty {
                    onboarding
                } else {
                    serverList
                }
            }
            .appBackground()
            .navigationTitle("服务器")
            .toolbar {
                if !app.servers.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showAdd = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("添加服务器")
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddServerView()
            }
            .confirmationDialog(
                "删除服务器",
                isPresented: Binding(
                    get: { deleteTarget != nil },
                    set: { if !$0 { deleteTarget = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    if let server = deleteTarget {
                        app.deleteServer(server)
                    }
                    deleteTarget = nil
                }
                Button("取消", role: .cancel) { deleteTarget = nil }
            } message: {
                Text("只会移除本机保存的地址，不影响 NAS 上的数据。")
            }
        }
    }

    private var onboarding: some View {
        VStack(spacing: 26) {
            Spacer()
            BrandIcon(size: 88)

            VStack(spacing: 10) {
                Text("连接你的 NAS")
                    .font(.title.weight(.bold))
                Text("输入 NAS 上媒体下载服务的地址，登录后即可远程探测、下载与管理视频。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            Button {
                showAdd = true
            } label: {
                Label("添加服务器", systemImage: "plus.circle.fill")
                    .padding(.horizontal, 8)
            }
            .primaryAction()

            Text("地址示例：192.168.1.10:8080\n支持 HTTP 与 HTTPS，也可使用反向代理域名。")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(24)
    }

    private var serverList: some View {
        List {
            Section {
                ForEach(app.servers) { server in
                    Button {
                        Task { await app.select(server) }
                    } label: {
                        ServerRow(server: server, isSelected: server.id == app.selectedServerID)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleteTarget = server
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            } header: {
                Text("我的服务器")
            } footer: {
                Text("轻点即可连接。连接成功后会检查登录状态，已登录则直接进入控制台。")
            }

            Section {
                Button {
                    showAdd = true
                } label: {
                    Label("添加服务器", systemImage: "plus")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }
}

/// 服务器列表行。
private struct ServerRow: View {
    let server: Server
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(systemName: "externaldrive.connected.to.line.below", size: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(server.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(server.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.accent)
                    .imageScale(.large)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// 添加服务器：先测试 /api/health，再保存并连接。
struct AddServerView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var address = ""
    @State private var testing = false
    @State private var error: String?

    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case address
    }

    private var canSubmit: Bool {
        !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !testing
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称（可选）", text: $name)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .address }

                    TextField("服务器地址", text: $address)
                        .focused($focusedField, equals: .address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit { submit() }
                } header: {
                    Text("服务器信息")
                } footer: {
                    Text("示例：192.168.1.10:8080、https://nas.example.com。未填写协议时默认使用 HTTP。")
                }

                Section {
                    Button {
                        submit()
                    } label: {
                        HStack {
                            Spacer()
                            if testing {
                                ProgressView()
                                    .controlSize(.small)
                                Text("正在连接…")
                            } else {
                                Label("测试并保存", systemImage: "bolt.horizontal.circle")
                            }
                            Spacer()
                        }
                    }
                    .disabled(!canSubmit)
                } footer: {
                    if let error {
                        Text(error)
                            .foregroundStyle(Theme.danger)
                    } else {
                        Text("将先访问服务的健康检查接口，确认地址可用后保存。")
                    }
                }
            }
            .navigationTitle("添加服务器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(testing)
                }
            }
            .onAppear { focusedField = .address }
        }
        .interactiveDismissDisabled(testing)
    }

    private func submit() {
        guard canSubmit else { return }
        testing = true
        error = nil
        Task {
            do {
                try await app.addServer(name: name, address: address)
                dismiss()
            } catch {
                self.error = APIError.describe(error)
                testing = false
            }
        }
    }
}
