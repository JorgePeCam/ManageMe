import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State private var showCloudKey = false

    var body: some View {
        NavigationStack {
            List {
                // AI Section
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "brain.head.profile")
                            .font(.title3)
                            .foregroundStyle(Color.appAccent)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.activeProviderName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(viewModel.aiStatusText)
                                .font(.caption)
                                .foregroundStyle(viewModel.isOnDeviceAIActive ? Color.appSuccess : .secondary)
                        }

                        Spacer()

                        Image(systemName: viewModel.isAIAvailable ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(viewModel.isOnDeviceAIActive ? Color.appSuccess : .secondary)
                    }
                } header: {
                    Text("Inteligencia Artificial")
                } footer: {
                    Text(viewModel.aiFooterText)
                }

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        if showCloudKey {
                            TextField("sk-...", text: $viewModel.openAIAPIKey)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                        } else {
                            SecureField("sk-...", text: $viewModel.openAIAPIKey)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                        }

                        Toggle("Mostrar clave", isOn: $showCloudKey)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Button("Guardar clave") {
                            viewModel.saveOpenAIAPIKey()
                        }
                        .disabled(viewModel.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Spacer()

                        Button("Eliminar clave", role: .destructive) {
                            viewModel.clearOpenAIAPIKey()
                        }
                    }
                } header: {
                    Text("Fallback OpenAI (opcional)")
                } footer: {
                    Text("La clave se guarda en el llavero del dispositivo.")
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
                        Label("Versión", systemImage: "info.circle")
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
