# ManageMe

ManageMe es una app iOS de **gestión documental con búsqueda semántica y preguntas sobre tus propios archivos**.
La idea es simple: importas documentos (PDF, imágenes, texto, Word/Excel), la app extrae y trocea el contenido, genera embeddings en local y luego te deja consultar todo desde una interfaz de chat.

---

## 1) Qué problema resuelve

Cuando tienes información repartida en muchos archivos (apuntes, tickets, PDFs, capturas, etc.), encontrar una respuesta rápida cuesta tiempo.

ManageMe convierte ese conjunto de documentos en una base consultable:

- Importas archivos desde el sistema o cámara.
- La app procesa el contenido automáticamente.
- Puedes hacer preguntas en lenguaje natural.
- Obtienes respuestas con citas a fragmentos concretos.

---

## 2) Funcionalidades principales

- **Biblioteca de documentos** con vista en cuadrícula.
- **Importación** desde archivos y cámara.
- **Procesamiento automático** de documentos:
  - extracción de texto,
  - fragmentación (chunking),
  - embeddings,
  - indexado local.
- **Búsqueda híbrida**:
  - semántica (vectores + similitud coseno),
  - palabras clave (FTS5 en SQLite).
- **Chat de preguntas y respuestas** sobre tus documentos.
- **Citas** en cada respuesta para trazabilidad.
- **Ajustes** para API key (OpenAI), reindexación y borrado de datos.

---

## 3) Arquitectura del proyecto

La estructura está organizada por capas y features:

```text
ManageMe/
├── Features/
│   ├── Library/         # Biblioteca e importación
│   ├── DocumentDetail/  # Vista detalle de documento
│   ├── Chat/            # Preguntas/respuestas
│   ├── Settings/        # Configuración y mantenimiento
│   └── Import/          # ImagePicker / entrada de ficheros
├── Core/
│   ├── Models/          # Modelos de dominio y DB
│   ├── Database/        # Repositorios + configuración GRDB
│   ├── Services/        # Extracción, chunking, embeddings, QA...
│   └── Theme.swift      # Estilo visual común
└── AI/                  # Recursos del modelo/tokenizer
```

### Componentes clave

- **`DocumentRepository`**: CRUD de documentos y gestión de archivos físicos.
- **`ChunkRepository`**: persistencia de chunks, vectores y consultas híbridas.
- **`DocumentProcessor`**: pipeline de procesado end-to-end.
- **`EmbeddingService`**: genera embeddings de texto.
- **`QAService`**: orquesta proveedores de respuesta (Foundation Models / OpenAI).

---

## 4) Flujo completo de datos

Este es el flujo más importante del proyecto.

### A. Ingesta

1. Usuario importa archivo (o hace foto).
2. Se guarda copia local en `Documents/files/`.
3. Se crea registro `Document` con estado inicial `pending`.

### B. Procesado

`DocumentProcessor` ejecuta:

1. **Extract text**: detecta tipo y extrae texto.
2. **Chunking**: divide en fragmentos manejables.
3. **Embeddings**: crea vector para cada chunk.
4. **Persistencia**:
   - guarda `DocumentChunk`,
   - guarda `ChunkVector`.
5. Marca el documento como `ready`.

Si algo falla, se pasa a estado `error` con mensaje.

### C. Consulta

Cuando el usuario pregunta en el chat:

1. Se genera embedding de la consulta.
2. Se ejecuta búsqueda híbrida:
   - vectorial por similitud coseno,
   - keywords con FTS5.
3. Se combinan scores y se seleccionan top resultados.
4. Se construyen citas.
5. Se responde con:
   - proveedor LLM (si está disponible), o
   - fallback extractivo (si no hay proveedor).

---

## 5) Modelo de datos (alto nivel)

- **`Document`**: metadatos del archivo, estado de procesamiento, tamaño, rutas, contenido extraído.
- **`DocumentChunk`**: fragmentos textuales indexables.
- **`ChunkVector`**: embedding binario asociado a cada chunk.
- **`SearchResult`**: resultado combinado de búsqueda para el chat.
- **`ChatMessage` / `Citation`**: salida de conversación y referencias.

---

## 6) IA y proveedores de respuesta

La app contempla dos formas de responder:

1. **Foundation Models (on-device)** cuando esté disponible en el runtime.
2. **OpenAI** como fallback/configuración externa.

`QAService` selecciona el primer proveedor disponible y construye un prompt basado **solo en fragmentos recuperados** para minimizar alucinaciones.

---

## 7) Persistencia local y privacidad

- Base de datos local con **GRDB/SQLite**.
- Archivos en sandbox de la app (`Documents/files`).
- Indexado y búsqueda local.
- El envío a proveedor externo solo aplica si configuras API key y se usa ese provider.

---

## 8) Configuración de Ajustes

En Ajustes puedes:

- guardar API key de OpenAI,
- revisar proveedor activo,
- ver conteo/espacio de documentos,
- reindexar todo,
- borrar todos los datos.

---

## 9) Tecnologías usadas

- **Swift + SwiftUI**
- **GRDB (SQLite)**
- **Accelerate/vDSP** para operaciones vectoriales
- **UniformTypeIdentifiers**, `FileImporter`, cámara/fotos

---

## 10) Estado actual del proyecto

Es una base muy buena de MVP para un “segundo cerebro” personal:

- ya cubre el ciclo completo de ingesta → indexado → consulta,
- tiene fallback cuando no hay proveedor LLM,
- y está preparado para evolucionar en calidad de extracción, ranking y UX.

---

## 11) Siguientes mejoras recomendadas

- Mejorar cobertura de tests (pipeline y edge-cases de búsqueda).
- Añadir métricas de procesamiento (tiempos por fase).
- Afinar ranking híbrido con señales de recencia/tipo de documento.
- Soportar highlighting de snippets en resultados.
- Mejorar manejo de errores visibles (mensajes por caso específico).

---

## 12) Nota para desarrollo local

Este repo es un proyecto iOS/Xcode. Para ejecutar y testear completamente necesitarás entorno Apple (Xcode + simulador/dispositivo iOS).

