# ManageMe

ManageMe es una app iOS para **organizar documentos y hacer preguntas sobre su contenido** con búsqueda semántica local.

Importas archivos, la app extrae texto, lo trocea, genera embeddings y luego responde en chat con citas.

---

## Qué resuelve

Cuando tienes información repartida en PDFs, fotos y documentos ofimáticos, recuperar una respuesta concreta es lento.

ManageMe te permite:

- centralizar tus archivos en una biblioteca,
- organizarlos en carpetas,
- consultar todo en lenguaje natural,
- ver de qué documento sale cada respuesta.

---

## Funcionalidades actuales

- Biblioteca con documentos y **carpetas** (crear, renombrar, borrar, navegar, mover documentos).
- Importación desde archivos y cámara.
- **Share Extension** para compartir archivos y contenido desde otras apps a ManageMe.
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

```text
ManageMe/
├── Features/
│   ├── Library/         # Biblioteca, carpetas, importación
│   ├── DocumentDetail/  # Vista de detalle de documento
│   ├── Chat/            # Preguntas/respuestas
│   ├── Settings/        # Estado IA y mantenimiento
│   └── Import/          # ImagePicker
├── Core/
│   ├── Models/          # Document, Folder, Chunk, Conversation...
│   ├── Database/        # AppDatabase + repositorios
│   ├── Services/        # Extracción, chunking, embeddings, QA
│   ├── Sync/            # CKSyncEngine + mapeo CloudKit
│   └── Theme.swift
└── AI/                  # Tokenizer y recursos de modelos
```

Componentes clave:

- `DocumentProcessor`: pipeline de ingesta y procesamiento.
- `ChunkRepository`: búsqueda vectorial + FTS híbrida.
- `FolderRepository`: operaciones de carpetas.
- `QAService`: cadena de proveedores de respuesta.
- `SyncCoordinator`: sincronización bidireccional con iCloud.

---

## IA y privacidad

`QAService` usa esta cadena de fallback:

1. Apple Foundation Models (on-device), si está disponible.
2. Respuesta extractiva local, como último recurso.

---

## Sincronización iCloud

ManageMe incluye sincronización bidireccional con CloudKit (base de datos privada del usuario):

- sincroniza documentos, carpetas, conversaciones y mensajes,
- mantiene una cola local de cambios pendientes,
- reintenta envíos y descargas cuando la app vuelve a estar activa.

Requisitos:

- iOS 17 o superior,
- sesión de iCloud activa en el dispositivo,
- mismo Apple ID en los dispositivos a sincronizar.

---

## Share Extension

ManageMe incluye una extensión de compartir para guardar contenido sin abrir la app manualmente.

Flujo:

1. Desde Safari, Mail, WhatsApp u otra app, usa Compartir -> `Guardar en ManageMe`.
2. La extensión copia el contenido compartido a un inbox compartido (`App Group`).
3. Al abrir/activar ManageMe, la app importa ese inbox y lanza su pipeline normal (extract -> chunk -> embeddings).

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
xcodebuild -list -project ManageMe.xcodeproj
xcodebuild test -project ManageMe.xcodeproj -scheme ManageMe -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1'
```

---

## Estado del proyecto

El proyecto ya cubre el flujo completo:

ingesta -> indexado -> organización en carpetas -> consulta en chat.

Áreas naturales de mejora:

- optimizar escalado de búsqueda vectorial en colecciones grandes,
- ampliar tests de pipeline (extractores y ranking),
- endurecer warnings de concurrencia para Swift 6 estricto.
