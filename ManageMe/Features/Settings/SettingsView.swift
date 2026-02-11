import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        NavigationStack {
            List {
                Section("Almacenamiento") {
                    HStack {
                        Text("Documentos")
                        Spacer()
                        Text("\(viewModel.documentCount)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Espacio usado")
                        Spacer()
                        Text(viewModel.storageUsed)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("IA") {
                    HStack {
                        Text("Modelo de embeddings")
                        Spacer()
                        Text(viewModel.embeddingModelStatus)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Acciones") {
                    Button("Reindexar todos los documentos") {
                        viewModel.reindexAll()
                    }

                    Button("Borrar todos los datos", role: .destructive) {
                        viewModel.showDeleteConfirmation = true
                    }
                }

                Section("Acerca de") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Ajustes")
            .alert("Borrar todos los datos", isPresented: $viewModel.showDeleteConfirmation) {
                Button("Cancelar", role: .cancel) {}
                Button("Borrar", role: .destructive) {
                    viewModel.deleteAllData()
                }
            } message: {
                Text("Se eliminaran todos los documentos y datos. Esta accion no se puede deshacer.")
            }
            .task {
                await viewModel.loadStats()
            }
        }
    }
}
