import SwiftUI

/// 主界面：与 Web 端一致的五个功能标签。
struct MainTabView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app

        TabView(selection: $app.selectedTab) {
            DownloadView()
                .tabItem { Label(AppTab.download.title, systemImage: AppTab.download.systemImage) }
                .tag(AppTab.download)

            BangumiView()
                .tabItem { Label(AppTab.bangumi.title, systemImage: AppTab.bangumi.systemImage) }
                .tag(AppTab.bangumi)

            JobsView()
                .tabItem { Label(AppTab.jobs.title, systemImage: AppTab.jobs.systemImage) }
                .tag(AppTab.jobs)

            FileBrowserView(path: "", title: "文件")
                .tabItem { Label(AppTab.files.title, systemImage: AppTab.files.systemImage) }
                .tag(AppTab.files)

            AccountView()
                .tabItem { Label(AppTab.account.title, systemImage: AppTab.account.systemImage) }
                .tag(AppTab.account)
        }
        .tint(Theme.accent)
        .overlay(alignment: .top) {
            ToastOverlay(toast: app.toast)
                .animation(.smooth(duration: 0.25), value: app.toast)
        }
    }
}
