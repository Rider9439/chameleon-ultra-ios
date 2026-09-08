import SwiftUI

@main
struct ChameleonUltraApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
        }
    }
}

/// 主 Tab 布局（对照参考 App：设备 / 卡槽 / 读卡 / 实验室 / 我的）
struct MainTabView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            DeviceView()
                .tabItem { Label("设备", systemImage: "link.circle.fill") }
                .tag(0)

            SlotsView()
                .tabItem { Label("卡槽", systemImage: "square.grid.3x3.fill") }
                .tag(1)

            ReaderView()
                .tabItem { Label("读卡", systemImage: "wave.3.right.circle.fill") }
                .tag(2)

            LabView()
                .tabItem { Label("实验室", systemImage: "flask.fill") }
                .tag(3)

            ProfileView()
                .tabItem { Label("我的", systemImage: "person.crop.circle.fill") }
                .tag(4)
        }
        .alert("提示", isPresented: $appState.showError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(appState.errorMessage)
        }
        .onAppear {
            // 恢复围栏监控状态
            appState.geofence.resumeMonitoring()
        }
    }
}
