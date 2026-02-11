import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            LibraryView()
                .tabItem {
                    Label("Biblioteca", systemImage: "doc.on.doc")
                }

            ChatView()
                .tabItem {
                    Label("Preguntar", systemImage: "bubble.left.and.text.bubble.right")
                }

            SettingsView()
                .tabItem {
                    Label("Ajustes", systemImage: "gear")
                }
        }
    }
}
