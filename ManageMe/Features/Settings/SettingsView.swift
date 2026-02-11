import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        NavigationStack {
            List {
                // AI Section - Highlighted
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Image(systemName: "brain.head.profile")
                                .font(.title3)
                                .foregroundStyle(Color.appAccent)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Proveedor de IA")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text(viewModel.activeProviderName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundStyle(Color.appAccent)
                            .frame(width: 24)

                        SecureField("API Key de OpenAI", text: $viewModel.apiKey)
                            .textContentType(.password)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onChange(of: viewModel.apiKey) {
                                viewModel.saveApiKey()
                            }
                    }

                    if viewModel.apiKey.isEmpty {
                        Label("Necesitas una API key para respuestas inteligentes",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.appWarning)
                    } else {
                        Label("API key configurada",
                              systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.appSuccess)
                    }
                } header: {
                    Text("Inteligencia Artificial")
                } footer: {
                    Text("Consigue tu API key en platform.openai.com.\nSe usa GPT-4o mini (rapido y economico).")
                }

                // Storage
                Section("Almacenamiento") {
                    HStack {
                        Label("Documentos", systemImage: "doc.on.doc")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(viewModel.documentCount)")
                            .foregroundStyle(.secondary)
                            .fontWeight(.medium)
                    }

                    HStack {
                        Label("Espacio usado", systemImage: "internaldrive")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(viewModel.storageUsed)
                            .foregroundStyle(.secondary)
                            .fontWeight(.medium)
                    }

                    HStack {
                        Label("Embeddings", systemImage: "brain")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(viewModel.embeddingModelStatus)
                            .foregroundStyle(.secondary)
                            .fontWeight(.medium)
                    }
                }

                // Actions
                Section("Acciones") {
                    Button {
                        viewModel.reindexAll()
                    } label: {
                        Label("Reindexar documentos", systemImage: "arrow.clockwise")
                            .foregroundStyle(Color.appAccent)
                    }

                    Button(role: .destructive) {
                        viewModel.showDeleteConfirmation = true
                    } label: {
                        Label("Borrar todos los datos", systemImage: "trash")
                    }
                }

                // About
                Section {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Acerca de")
                } footer: {
                    Text("ManageMe — Tu segundo cerebro digital")
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }
            }
            .navigationTitle("Ajustes")
            .tint(Color.appAccent)
            .alert("Borrar todos los datos", isPresented: $viewModel.showDeleteConfirmation) {
                Button("Cancelar", role: .cancel) {}
                Button("Borrar todo", role: .destructive) {
                    viewModel.deleteAllData()
                }
            } message: {
                Text("Se eliminarán todos los documentos y datos. Esta acción no se puede deshacer.")
            }
            .task {
                await viewModel.loadStats()
            }
            .alert("Error", isPresented: Binding(
                get: { viewModel.userErrorMessage != nil },
                set: { isPresented in
                    if !isPresented { viewModel.userErrorMessage = nil }
                }
            )) {
                Button("OK", role: .cancel) {
                    viewModel.userErrorMessage = nil
                }
            } message: {
                Text(viewModel.userErrorMessage ?? "Ha ocurrido un error.")
            }
        }
    }
}
