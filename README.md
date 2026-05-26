# DocumentBrain

DocumentBrain es una app iOS para **organizar documentos y hacer preguntas sobre su contenido** con búsqueda semántica local.

Importas archivos, la app extrae texto, lo trocea, genera embeddings y luego responde en chat con citas.

---

## Qué resuelve

Cuando tienes información repartida en PDFs, fotos y documentos ofimáticos, recuperar una respuesta concreta es lento.

DocumentBrain te permite:

- centralizar tus archivos en una biblioteca,
- organizarlos en carpetas,
- consultar todo en lenguaje natural,
- ver de qué documento sale cada respuesta.

---

## Funcionalidades actuales

- Biblioteca con documentos y **carpetas** (crear, renombrar, borrar, navegar, mover documentos).
- Importación desde archivos y cámara.
- **Share Extension** para compartir archivos y contenido desde otras apps a DocumentBrain.
- Procesamiento automático:
  - extracción de texto,
  - chunking,
  - embeddings,
  - persistencia en SQLite.
- Búsqueda híbrida:
  - similitud semántica (coseno),
  - FTS5 por keywords.
- Chat con:
  - respuestas con citas,
  - streaming cuando el proveedor lo permite,
  - fallback extractivo si falla IA.
- Ajustes de mantenimiento:
  - estado de IA/proveedor activo,
  - estado de sincronización iCloud,
  - reindexado,
  - borrado total de datos.

---

## Tipos de archivo soportados

- `PDF` (texto nativo + OCR cuando hace falta).
- Imágenes (`jpg`, `png`, `heic`, etc.) con OCR.
- `DOCX`.
- `XLSX` (lectura de hojas + shared strings).
- Texto plano (`txt`, `md`, `csv`, `rtf`).

---

## Arquitectura

### Estructura general

```text
DocumentBrain.xcodeproj/          # Proyecto Xcode y esquemas de build
DocumentBrain/                    # App principal
├── DocumentBrainApp.swift        # Entry point: arranca SyncCoordinator y decide Onboarding/MainTab
├── Core/                    # Capa de negocio (sin UI)
│   ├── Models/              # Entidades del dominio
│   ├── Database/            # Persistencia local con GRDB/SQLite
│   ├── Services/            # Lógica de extracción, indexado y Q&A
│   ├── Sync/                # Sincronización iCloud (CKSyncEngine)
│   └── Theme.swift          # Colores, tipografías y estilos globales
├── Features/                # Pantallas SwiftUI + ViewModels
│   ├── Library/             # Biblioteca, carpetas e importación
│   ├── DocumentDetail/      # Vista de detalle de documento
│   ├── Chat/                # Preguntas y respuestas
│   ├── Settings/            # Idioma, estado IA y mantenimiento
│   ├── Onboarding/          # Primer arranque
│   └── Import/              # ImagePicker (cámara/galería)
├── AI/                      # Tokenizer y matemática vectorial
└── Assets.xcassets          # Iconos y colores
DocumentBrainShareExtension/      # Extensión para compartir desde otras apps
DocumentBrainTests/               # Tests unitarios
DocumentBrainUITests/             # Tests de UI
```

### `Core/Models/` — Entidades

| Fichero | Qué representa |
|---|---|
| `Document.swift` | Documento importado (PDF, imagen, DOCX, etc.) |
| `DocumentChunk.swift` | Fragmento de texto con su embedding vectorial |
| `Folder.swift` | Carpeta que agrupa documentos |
| `Conversation.swift` | Historial de chat y mensajes |
| `AppLanguage.swift` | Soporte ES/EN (prompts, etiquetas, idioma activo) |
| `Extensions.swift` | Helpers comunes |

### `Core/Database/` — Persistencia

| Fichero | Responsabilidad |
|---|---|
| `AppDatabase.swift` | Setup del schema GRDB y migraciones |
| `DocumentRepository.swift` | CRUD de documentos y gestión de ficheros en sandbox |
| `ChunkRepository.swift` | Búsqueda híbrida (vectorial + FTS5) |
| `FolderRepository.swift` | Operaciones de carpetas |
| `ConversationRepository.swift` | Persistencia de chats y mensajes |

### `Core/Services/` — Lógica de negocio

| Fichero | Responsabilidad |
|---|---|
| `TextExtractionService.swift` | Extrae texto de PDF, imágenes (OCR Vision), DOCX, XLSX, ZIP |
| `ChunkingService.swift` | Divide el texto en fragmentos solapados |
| `EmbeddingService.swift` | Genera embeddings vectoriales de los chunks |
| `DocumentProcessor.swift` | Orquesta el pipeline: extracción → chunking → embeddings |
| `QAService.swift` | Cadena de fallback de proveedores de respuesta |
| `GeminiQAProvider.swift` | Proveedor cloud Gemini Flash (con streaming) |
| `FoundationModelQAProvider.swift` | Proveedor on-device Apple Intelligence (iOS 26+) |
| `SharedInboxImporter.swift` | Importa ficheros de la Share Extension al abrir la app |
| `ThumbnailService.swift` | Genera miniaturas de documentos |
| `ZIPReader.swift` | Descomprime ZIPs para procesar su contenido |

### `Core/Sync/` — iCloud

| Fichero | Responsabilidad |
|---|---|
| `SyncCoordinator.swift` | Orquesta la sincronización bidireccional con CloudKit |
| `SyncFileManager.swift` | Gestiona los ficheros físicos en iCloud Drive |
| `RecordMapper.swift` | Mapea modelos locales a/desde registros CloudKit |

### `AI/` — Motor semántico local

| Fichero | Responsabilidad |
|---|---|
| `BERTTokenizer.swift` | Tokenizador BERT para preparar texto antes de embeddings |
| `VectorMath.swift` | Similitud coseno y operaciones vectoriales |
| `vocab.txt` / `qa_vocab.txt` | Vocabulario del modelo |

### `Features/` — UI

Cada feature sigue el patrón `View` + `ViewModel`:

| Feature | Función |
|---|---|
| `Library/` | Biblioteca con tabs, carpetas, búsqueda y tarjetas de documento |
| `Chat/` | Interfaz de Q&A con streaming y citas |
| `DocumentDetail/` | Previsualización, metadata y acciones sobre un documento |
| `Settings/` | Idioma, proveedor IA activo, reindexado, borrado total |
| `Onboarding/` | Pantalla inicial al primer arranque |
| `Import/` | `ImagePicker` para cámara/galería |

### `DocumentBrainShareExtension/`

`ShareViewController.swift` recibe ficheros y URLs compartidos desde otras apps (Safari, Mail, WhatsApp…) y los deposita en el inbox compartido vía App Group. Al activar la app, `SharedInboxImporter` los procesa.

### Flujo principal

```text
Importar  →  TextExtractionService  →  ChunkingService  →  EmbeddingService
                                                                    ↓
                                                          ChunkRepository (SQLite)
                                                                    ↓
Pregunta  →  BERTTokenizer  →  similitud coseno (VectorMath)  →  chunks relevantes
                                                                    ↓
                                          QAService  →  1. Gemini Flash (streaming)
                                                     →  2. Apple Intelligence (fallback)
                                                     →  3. Respuesta extractiva
```

### Componentes clave

- `DocumentProcessor`: pipeline de ingesta y procesamiento.
- `ChunkRepository`: búsqueda híbrida vectorial + FTS5.
- `QAService`: cadena de proveedores de respuesta con fallback automático.
- `SyncCoordinator`: sincronización bidireccional con iCloud.
- `SharedInboxImporter`: puente entre la Share Extension y el pipeline.

---

## IA y privacidad

`QAService` usa esta cadena de fallback:

1. **Gemini Flash** (cloud, free tier) — primaria, mejor calidad y streaming.
2. **Apple Foundation Models** (on-device, iOS 26+) — cuando no hay red o se agota el cupo.
3. **Respuesta extractiva local** — último recurso si fallan los anteriores.

El idioma de la respuesta sigue al idioma activo de la app (`AppLanguage`).

---

## Sincronización iCloud

DocumentBrain incluye sincronización bidireccional con CloudKit (base de datos privada del usuario):

- sincroniza documentos, carpetas, conversaciones y mensajes,
- mantiene una cola local de cambios pendientes,
- reintenta envíos y descargas cuando la app vuelve a estar activa.

Requisitos:

- iOS 17 o superior,
- sesión de iCloud activa en el dispositivo,
- mismo Apple ID en los dispositivos a sincronizar.

---

## Share Extension

DocumentBrain incluye una extensión de compartir para guardar contenido sin abrir la app manualmente.

Flujo:

1. Desde Safari, Mail, WhatsApp u otra app, usa Compartir -> `Guardar en DocumentBrain`.
2. La extensión copia el contenido compartido a un inbox compartido (`App Group`).
3. Al abrir/activar DocumentBrain, la app importa ese inbox y lanza su pipeline normal (extract -> chunk -> embeddings).

---

## Persistencia

- Base de datos local con **GRDB/SQLite**.
- Archivos en sandbox de la app (`Documents/files`).
- Índice de búsqueda híbrida local.

---

## Desarrollo local

Requisitos:

- macOS con Xcode.
- Simulador iOS o dispositivo.

Comandos útiles:

```bash
xcodebuild -list -project DocumentBrain.xcodeproj
xcodebuild test -project DocumentBrain.xcodeproj -scheme DocumentBrain -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1'
```

---

## Estado del proyecto

El proyecto ya cubre el flujo completo:

ingesta -> indexado -> organización en carpetas -> consulta en chat.

Áreas naturales de mejora:

- optimizar escalado de búsqueda vectorial en colecciones grandes,
- ampliar tests de pipeline (extractores y ranking),
- endurecer warnings de concurrencia para Swift 6 estricto.
