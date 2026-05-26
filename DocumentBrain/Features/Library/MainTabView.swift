import SwiftUI

struct MainTabView: View {
    private var lang: AppLanguage { AppLanguage.current }

    var body: some View {
        TabView {
            LibraryView()
                .tabItem {
                    Label(lang.tabLibrary, systemImage: "square.grid.2x2.fill")
                }

            ChatView()
                .tabItem {
                    Label(lang.tabChat, systemImage: "bubble.left.and.bubble.right.fill")
                }

            SettingsView()
                .tabItem {
                    Label(lang.tabSettings, systemImage: "gearshape.fill")
                }
        }
        .tint(Color.appAccent)
    }
}
