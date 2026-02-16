import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()

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

                // iCloud Sync
                if #available(iOS 17.0, *) {
                    iCloudSyncSection
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

    // MARK: - iCloud Sync Section

    @available(iOS 17.0, *)
    private var iCloudSyncSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "icloud")
                    .font(.title3)
                    .foregroundStyle(SyncCoordinator.shared.iCloudAvailable ? Color.appAccent : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Sincronización iCloud")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if SyncCoordinator.shared.isSyncing {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Sincronizando...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if let lastSync = SyncCoordinator.shared.lastSyncDate {
                        Text("Última sync: \(lastSync, style: .relative) atrás")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if SyncCoordinator.shared.iCloudAvailable {
                        Text("Activa")
                            .font(.caption)
                            .foregroundStyle(Color.appSuccess)
                    } else {
                        Text("No disponible")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: SyncCoordinator.shared.iCloudAvailable ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(SyncCoordinator.shared.iCloudAvailable ? Color.appSuccess : .secondary)
            }

            if let error = SyncCoordinator.shared.syncError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("iCloud")
        } footer: {
            Text("Documentos, carpetas y conversaciones se sincronizan automáticamente entre tus dispositivos.")
        }
    }
}
