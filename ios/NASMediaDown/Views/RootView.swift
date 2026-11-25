import SwiftUI

/// 根据全局状态切换启动页、服务器列表、登录页与主界面。
struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            AppBackground()

            switch app.route {
            case .launch:
                LaunchView()
            case .servers:
                ServerListView()
            case .login:
                LoginView()
            case .main:
                MainTabView()
            }
        }
        .animation(.smooth(duration: 0.25), value: app.route)
        .task { await app.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, app.route == .main {
                Task { await app.jobs.refresh() }
            }
        }
    }
}

/// 启动与连接阶段的加载页。
private struct LaunchView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 22) {
            BrandIcon(size: 84)
            VStack(spacing: 6) {
                Text("媒体下载")
                    .font(.title2.weight(.bold))
                if let server = app.selectedServer {
                    Text("正在连接 \(server.name)…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView()
                .controlSize(.regular)
        }
        .padding(32)
    }
}
