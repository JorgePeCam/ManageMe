import SwiftUI

struct LibraryView: View {
    @StateObject private var viewModel = LibraryViewModel()
    @State private var searchText = ""
    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var folderToRename: Folder?
    @State private var renameFolderName = ""
    @State private var documentToMove: String?
    @State private var showMoveSheet = false

    private let columns = [
        GridItem(.flexible(), spacing: AppStyle.cardSpacing),
        GridItem(.flexible(), spacing: AppStyle.cardSpacing)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.documents.isEmpty && viewModel.folders.isEmpty && !viewModel.isInFolder {
                    emptyState
                } else {
                    contentGrid
                }
            }
            .navigationTitle(viewModel.currentFolderName)
            .navigationBarTitleDisplayMode(viewModel.isInFolder ? .inline : .large)
            .searchable(text: $searchText, prompt: "Buscar documentos...")
            .toolbar {
                if viewModel.isInFolder {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            viewModel.navigateBack()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Atrás")
                            }
                            .foregroundStyle(Color.appAccent)
                        }
                    }
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        filterMenu
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            viewModel.showImporter = true
                        } label: {
                            Label("Desde archivos", systemImage: "doc.badge.plus")
                        }

                        Button {
                            viewModel.showCamera = true
                        } label: {
                            Label("Hacer foto", systemImage: "camera")
                        }

                        Divider()

                        Button {
                            showNewFolderAlert = true
                        } label: {
                            Label("Nueva carpeta", systemImage: "folder.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.appAccent)
                    }
                }
            }
            .fileImporter(
                isPresented: $viewModel.showImporter,
                allowedContentTypes: viewModel.allowedContentTypes,
                allowsMultipleSelection: true
            ) { result in
                viewModel.handleFileImport(result: result)
            }
            .sheet(isPresented: $viewModel.showCamera) {
                ImagePicker(sourceType: .camera) { image in
                    viewModel.handleCameraCapture(image: image)
                }
            }
            .sheet(isPresented: $showMoveSheet) {
                moveToFolderSheet
            }
            .task {
                await viewModel.loadDocuments()
            }
            .onReceive(NotificationCenter.default.publisher(for: .sharedInboxDidImportDocuments)) { _ in
                Task {
                    await viewModel.loadDocuments()
                }
            }
            .alert("Nueva carpeta", isPresented: $showNewFolderAlert) {
                TextField("Nombre", text: $newFolderName)
                Button("Crear") {
                    viewModel.createFolder(name: newFolderName)
                    newFolderName = ""
                }
                Button("Cancelar", role: .cancel) { newFolderName = "" }
            }
            .alert("Renombrar carpeta", isPresented: Binding(
                get: { folderToRename != nil },
                set: { if !$0 { folderToRename = nil } }
            )) {
                TextField("Nombre", text: $renameFolderName)
                Button("Renombrar") {
                    if let folder = folderToRename {
                        viewModel.renameFolder(folder, newName: renameFolderName)
                    }
                    folderToRename = nil
                    renameFolderName = ""
                }
                Button("Cancelar", role: .cancel) {
                    folderToRename = nil
                    renameFolderName = ""
                }
            }
            .alert("Error", isPresented: Binding(
                get: { viewModel.userErrorMessage != nil },
                set: { if !$0 { viewModel.userErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { viewModel.userErrorMessage = nil }
            } message: {
                Text(viewModel.userErrorMessage ?? "Ha ocurrido un error.")
            }
        }
    }

    // MARK: - Filter Menu

    private var filterMenu: some View {
        Menu {
            Button {
                viewModel.filterType = nil
            } label: {
                Label("Todos", systemImage: viewModel.filterType == nil ? "checkmark" : "")
            }
            Divider()
            ForEach(FileType.allCases, id: \.self) { type in
                Button {
                    viewModel.filterType = type
                } label: {
                    Label(type.displayName, systemImage: type.systemImage)
                }
            }
        } label: {
            Image(systemName: viewModel.filterType != nil
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.appAccent)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(LinearGradient.accentSoftGradient)
                    .frame(width: 120, height: 120)

                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(Color.appAccent)
            }

            VStack(spacing: 8) {
                Text("Tu segundo cerebro")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Importa documentos y pregunta lo que\nnecesites saber sobre ellos")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button {
                    viewModel.showImporter = true
                } label: {
                    Label("Importar archivos", systemImage: "folder.fill")
                        .fontWeight(.semibold)
                        .frame(maxWidth: 220)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.appAccent)
                .controlSize(.large)

                Button {
                    viewModel.showCamera = true
                } label: {
                    Label("Escanear documento", systemImage: "camera.fill")
                        .frame(maxWidth: 220)
                }
                .buttonStyle(.bordered)
                .tint(Color.appAccent)
                .controlSize(.large)
            }

            Spacer()
        }
        .padding(AppStyle.paddingLarge)
    }

    // MARK: - Content Grid

    private var contentGrid: some View {
        ScrollView {
            // Item count header
            let totalItems = viewModel.folders.count + filteredDocuments.count
            if totalItems > 0 {
                HStack {
                    Text("\(totalItems) elemento\(totalItems == 1 ? "" : "s")")
                        .font(.footnote)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, AppStyle.padding)
                .padding(.top, 4)
            }

            LazyVGrid(columns: columns, spacing: AppStyle.cardSpacing) {
                // Folders first
                ForEach(viewModel.folders) { folder in
                    Button {
                        viewModel.navigateToFolder(folder)
                    } label: {
                        FolderCard(
                            folder: folder,
                            documentCount: viewModel.documentCounts[folder.id] ?? 0
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            renameFolderName = folder.name
                            folderToRename = folder
                        } label: {
                            Label("Renombrar", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            viewModel.deleteFolder(id: folder.id)
                        } label: {
                            Label("Eliminar carpeta", systemImage: "trash")
                        }
                    }
                }

                // Then documents
                ForEach(filteredDocuments) { document in
                    NavigationLink(value: document.id) {
                        DocumentCard(document: document)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            documentToMove = document.id
                            showMoveSheet = true
                        } label: {
                            Label("Mover a carpeta", systemImage: "folder")
                        }

                        if viewModel.isInFolder {
                            Button {
                                viewModel.moveDocument(document.id, toFolder: nil)
                            } label: {
                                Label("Sacar de carpeta", systemImage: "arrow.up.doc")
                            }
                        }

                        Button(role: .destructive) {
                            viewModel.deleteDocument(id: document.id)
                        } label: {
                            Label("Eliminar", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, AppStyle.padding)
            .padding(.bottom, AppStyle.padding)
        }
        .navigationDestination(for: String.self) { documentId in
            DocumentDetailView(documentId: documentId)
        }
    }

    // MARK: - Move Sheet

    private var moveToFolderSheet: some View {
        NavigationStack {
            List {
                if viewModel.isInFolder {
                    Button {
                        if let docId = documentToMove {
                            viewModel.moveDocument(docId, toFolder: nil)
                        }
                        showMoveSheet = false
                        documentToMove = nil
                    } label: {
                        Label("Raíz (sin carpeta)", systemImage: "house")
                    }
                }

                ForEach(viewModel.folders) { folder in
                    Button {
                        if let docId = documentToMove {
                            viewModel.moveDocument(docId, toFolder: folder.id)
                        }
                        showMoveSheet = false
                        documentToMove = nil
                    } label: {
                        Label(folder.name, systemImage: "folder.fill")
                    }
                }

                if viewModel.folders.isEmpty && !viewModel.isInFolder {
                    Text("No hay carpetas. Crea una primero.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Mover a...")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        showMoveSheet = false
                        documentToMove = nil
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers

    private var filteredDocuments: [Document] {
        let docs = viewModel.filteredDocuments
        if searchText.isEmpty { return docs }
        return docs.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }
}
