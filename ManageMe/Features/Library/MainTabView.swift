import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            LibraryView()
                .tabItem {
                    Label("Biblioteca", systemImage: "square.grid.2x2.fill")
                }

            ChatView()
                .tabItem {
                    Label("Preguntar", systemImage: "bubble.left.and.bubble.right.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Ajustes", systemImage: "gearshape.fill")
                }
        }
        .tint(Color.appAccent)
    }
}
