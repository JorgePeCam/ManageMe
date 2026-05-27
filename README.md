# DocumentBrain

DocumentBrain es una app iOS para **organizar documentos y hacer preguntas sobre su contenido** mediante búsqueda semántica local y un asistente de IA conversacional.

Importas archivos, la app extrae el texto, lo trocea en fragmentos semánticos, genera embeddings vectoriales y luego responde tus preguntas en chat con citas al documento fuente. Todo el procesamiento pesado ocurre en el dispositivo.

---

## Qué resuelve

Cuando tienes información repartida en PDFs, fotos de documentos, hojas de cálculo y ficheros de texto, recuperar una respuesta concreta requiere abrir varios archivos y buscar manualmente.

DocumentBrain te permite:

- centralizar todos tus archivos en una biblioteca organizada,
- agruparlos en carpetas jerárquicas,
- consultar el contenido en lenguaje natural desde el chat,
- ver exactamente de qué fragmento del documento viene cada respuesta.

---

## Funcionalidades

### Biblioteca y organización

- Importación desde el sistema de archivos, cámara/galería y Share Extension.
- **Carpetas jerárquicas** con navegación por breadcrumb, creación, renombrado, borrado y movimiento de documentos a cualquier nivel.
- Tarjetas de documento con miniatura, estado de procesamiento y acción de reintento en caso de error.
- Filtros y ordenación por nombre, fecha y tipo.

### Procesamiento de documentos

- **Pipeline automático**: extracción de texto → chunking semántico → embeddings → persistencia.
- **Reintentos con backoff** (hasta 3 intentos, 2s y 4s de espera) para errores transitorios.
- **Recuperación al arrancar**: detecta documentos que quedaron en estados intermedios (crash durante el procesamiento) y los reprocesa automáticamente.
- **Reindexado completo** con overlay de progreso; se lanza automáticamente cuando se detecta un cambio de versión del modelo de embeddings.

### Búsqueda semántica

- **Hybrid search**: similitud coseno vectorial + FTS5 por palabras clave, combinados con deduplicación por ID de chunk.
- Umbral mínimo de score configurable (0.15 para vectorial, 0.25 en vectorial estricto).
- Expansión de contexto: los chunks recuperados se enriquecen con sus fragmentos vecinos en el documento para dar más contexto al LLM.
- Expansión de query corta para preguntas de seguimiento conversacional ("¿y el autor?").

### Chat conversacional

- Contexto multi-turn: las últimas 3 rondas de conversación se pasan al LLM para respuestas coherentes.
- **Streaming** de respuesta token a token.
- **Markdown completo**: headers, listas, código, separadores horizontales.
- **Citas tapeables**: cada respuesta muestra píldoras con la fuente; al tapear se abre el fragmento exacto recuperado.
- Selección de texto en mensajes del asistente (long-press para copiar).
- Fallback automático: Gemini Flash → Apple Intelligence (on-device, iOS 26+) → respuesta extractiva local.
- Desambiguación automática cuando los chunks recuperados corresponden a múltiples documentos distintos.

### Ajustes y mantenimiento

- Cambio de idioma (ES / EN) en tiempo real.
- Estado del proveedor de IA activo.
- Estado de sincronización iCloud.
- Reindexado con barra de progreso.
- Borrado completo de datos (documentos, conversaciones, caché de miniaturas).
- **Panel de debug RAG** (toggle Developer): muestra los chunks recuperados, sus scores, la query expandida y el proveedor usado, bajo cada respuesta.

---

## Tipos de archivo soportados

| Formato | Extracción |
|---|---|
| `PDF` | Texto nativo (PDFKit) + OCR automático cuando hace falta |
| Imágenes (`jpg`, `png`, `heic`, `webp`…) | OCR con Vision framework |
| `DOCX` | Parsing del XML interno |
| `XLSX` | Lectura de hojas y shared strings |
| `TXT`, `MD`, `CSV`, `RTF` | Lectura directa |
| `ZIP` | Descompresión y procesamiento de contenidos |

---

## Arquitectura

### Estructura de carpetas

```text
DocumentBrain.xcodeproj/
DocumentBrain/                        # App principal
├── DocumentBrainApp.swift            # Entry point: arranque, onboarding, SyncCoordinator
├── Core/
│   ├── Models/                       # Entidades del dominio
│   ├── Database/                     # Capa de persistencia (GRDB/SQLite)
│   ├── Services/                     # Lógica de negocio
│   ├── Sync/                         # Sincronización iCloud (CKSyncEngine)
│   └── Theme.swift                   # Colores, estilos y constantes de UI
├── Features/                         # Pantallas SwiftUI + ViewModels (MVVM)
│   ├── Library/
│   ├── DocumentDetail/
│   ├── Chat/
│   ├── Settings/
│   ├── Onboarding/
│   └── Import/
├── AI/                               # Tokenizador y matemática vectorial
├── PrivacyInfo.xcprivacy             # Privacy Manifest (App Store)
└── Assets.xcassets/
DocumentBrainShareExtension/          # Share Extension
DocumentBrainTests/                   # Tests unitarios
cloudflare-worker/                    # Proxy edge (Cloudflare Workers)
```

### Patrones de diseño

- **MVVM**: cada feature tiene su `View` (SwiftUI puro, sin lógica) y su `ViewModel` (`@MainActor`, `ObservableObject`).
- **Singleton controlado**: `EmbeddingService.shared` y `QAService.shared` evitan recargar modelos CoreML por operación.
- **Inyección de dependencias**: `EmbeddingServiceProtocol` permite mockear embeddings en tests sin cargar el modelo.
- **Repositorio**: cada entidad tiene su repositorio que encapsula las queries GRDB. Nunca se hace SQL libre fuera de los repositorios.

---

## Pipeline RAG

```
INGESTA
─────────────────────────────────────────────────────────────────────
Archivo  →  TextExtractionService  →  texto plano
                  ↓ hasta 3 reintentos (backoff 2s / 4s)
            ChunkingService  →  fragmentos semánticos (~800 chars / ~200 tokens)
                  ↓
            EmbeddingService  →  vector 384-dim (multi-qa-MiniLM-L6-cos-v1, CoreML)
                  ↓
            ChunkRepository  →  SQLite + índice FTS5

CONSULTA
─────────────────────────────────────────────────────────────────────
Pregunta del usuario
    ↓
expandedQuery (añade contexto de turns anteriores si la pregunta es corta)
    ↓
BERTTokenizer  →  vector de query (384-dim)
    ↓
hybridSearch:
    ├─ vectorSearch   (coseno ≥ 0.15, top-5)
    └─ FTS5 search    (AND estricto, relax a OR si < 2 resultados)
    ↓ deduplicación + merge por score
expandContextWithNeighbors  →  chunks ± 1 vecino para dar más contexto al LLM
    ↓
QAService  →  buildContextPrompt  →  últimas 3 rondas de historial
    ↓
    1. GeminiQAProvider   (cloud, streaming, multi-turn)
    2. FoundationModelQAProvider  (on-device, Apple Intelligence, iOS 26+)
    3. Respuesta extractiva  (fragmento local, sin LLM)
    ↓
Respuesta con markdown + citas tapeables
```

### Chunking semántico

`ChunkingService` divide el texto respetando la estructura semántica del documento:

1. **Normalización**: elimina espacios redundantes y colapsa líneas en blanco excesivas.
2. **División por párrafos** como unidad primaria de corte.
3. **Fusión de párrafos huérfanos**: párrafos de menos de 60 chars se fusionan con el siguiente.
4. **Ensamblado de chunks**: se acumulan párrafos hasta ~800 chars (~200 tokens). Los párrafos largos que no caben se dividen por límites de oración con guard de abreviaciones.
5. **Overlap semántico**: el último párrafo completo del chunk anterior se prepende al siguiente para evitar pérdida de contexto en los bordes.

Este enfoque mejora la precisión de recuperación frente a chunking por tamaño fijo porque cada fragmento tiende a contener una idea coherente.

### Modelo de embeddings

`multi-qa-MiniLM-L6-cos-v1` (384 dimensiones, cuantizado a CoreML):

- Entrenado específicamente para Q&A retrieval (pares pregunta-respuesta), a diferencia de modelos de propósito general.
- 6 capas transformer, eficiente en dispositivos con Neural Engine.
- Similitud coseno normalizada: todos los vectores se almacenan con norma unitaria para que el producto punto sea equivalente al coseno y la búsqueda sea más rápida.
- Al detectar un cambio de versión del modelo, la app lanza un reindexado automático completo con overlay de progreso.

---

## Seguridad

La seguridad es una prioridad de diseño, no un añadido posterior. A continuación se detalla cada capa.

### Arquitectura de proxy (clave API nunca en el dispositivo)

Las peticiones a Gemini no salen directamente del dispositivo. La app se comunica exclusivamente con un **Cloudflare Worker** desplegado en el edge que actúa como proxy seguro:

```
App iOS  ──(HTTPS + x-app-secret)──▶  Cloudflare Worker  ──(x-goog-api-key)──▶  Gemini API
```

- La clave de Gemini (`GEMINI_API_KEY`) vive como **secreto de entorno** en Cloudflare Workers y nunca toca el dispositivo del usuario.
- La app se autentica con el Worker mediante un **secreto compartido** (`x-app-secret`) en la cabecera HTTP, también almacenado en `Config.plist` (fichero excluido del control de versiones).
- Cualquier petición sin el header correcto recibe un `401 Unauthorized`.

**Por qué esto importa:** si la app fuera comprometida por ingeniería inversa, el atacante no obtendría ninguna clave de API, solo el secreto de app — que en el peor caso solo da acceso al proxy (sin coste directo para el atacante, con tus créditos).

### Cloudflare Worker — detalles técnicos

El Worker (`cloudflare-worker/src/index.js`) implementa:

| Mecanismo | Implementación |
|---|---|
| Autenticación de la app | Header `x-app-secret` validado contra variable de entorno `APP_SECRET` |
| Rate limiting por IP | KV de Cloudflare: 20 peticiones/IP/día; devuelve `429` al superarlo |
| Inyección de la clave | Header `x-goog-api-key` añadido server-side, nunca expuesto al cliente |
| Streaming SSE | Pass-through directo del body de Gemini con cabeceras CORS |
| CORS | Restringido a los métodos y headers que usa la app (`POST`, `x-app-secret`) |

### Persistencia local

- **GRDB/SQLite con queries parametrizadas**: toda la capa de base de datos usa binding de parámetros (la API de GRDB no permite SQL libre con interpolación de strings). Inyección SQL estructuralmente imposible.
- **FTS5**: el módulo `sanitizeFTSQuery` filtra y escapa los términos del usuario antes de construir la query FTS para evitar manipulación del índice.
- **Sin datos sensibles en UserDefaults**: ninguna clave, token ni credencial se almacena en UserDefaults ni en iCloud KV.
- Los archivos del usuario se guardan en el sandbox de la app (`Documents/files`) con los permisos estándar de iOS.

### Config.plist y secretos

`Config.plist` (que contiene `WorkerURL` y `AppSecret`) está en `.gitignore` y **nunca se sube al repositorio**. Cada instalación del proyecto requiere crear este fichero manualmente (o via CI secrets).

### Privacy Manifest (App Store)

`PrivacyInfo.xcprivacy` declara explícitamente:

- `NSPrivacyTracking: false` — la app no hace tracking de ningún tipo.
- `NSPrivacyTrackingDomains: []` — sin dominios de tracking.
- `NSPrivacyCollectedDataTypes: []` — no se recopilan datos del usuario.
- `NSPrivacyAccessedAPITypes`:
  - **UserDefaults** (razón CA92.1): almacena preferencias del usuario (idioma, onboarding completado).
  - **FileTimestamp** (razón C617.1): accede a fechas de modificación de ficheros del sandbox.

### Accesibilidad

Todos los controles interactivos tienen etiquetas VoiceOver y cumplen el mínimo de 44×44 pt de área táctil recomendado por Apple HIG. Los iconos decorativos están marcados como `accessibilityHidden(true)`.

---

## IA y privacidad

`QAService` implementa una cadena de fallback:

| Prioridad | Proveedor | Requisitos | Características |
|---|---|---|---|
| 1 | **Gemini Flash** (cloud) | Conexión a internet | Mejor calidad, streaming, multi-turn |
| 2 | **Apple Foundation Models** (on-device) | iOS 26+, Apple Intelligence activo | Sin red, privacidad total, sin coste |
| 3 | **Respuesta extractiva** (local) | Ninguno | Devuelve el fragmento más relevante sin LLM |

- El idioma de las respuestas sigue al idioma activo de la app (`AppLanguage`): el system prompt se genera en el idioma seleccionado.
- El historial conversacional (últimas 3 rondas) se pasa al LLM para respuestas coherentes en conversaciones multi-pregunta.
- Cuando los resultados recuperados corresponden a múltiples documentos, el prompt instruye al LLM a desambiguar en lugar de mezclar respuestas.

---

## Sincronización iCloud

DocumentBrain incluye sincronización bidireccional con CloudKit (base de datos privada del usuario):

- Sincroniza documentos, carpetas, conversaciones y mensajes.
- Mantiene una cola local de cambios pendientes con reintento cuando la app vuelve a estar activa.
- `SyncCoordinator` (iOS 17+) orquesta la sincronización; en iOS 16 la app funciona sin sync.
- El estado de sincronización es visible en Ajustes (indicador activo / sincronizando / error).

**Requisitos**: iOS 17+, sesión de iCloud activa, mismo Apple ID en los dispositivos.

---

## Share Extension

La extensión `DocumentBrainShareExtension` permite guardar contenido directamente desde otras apps:

1. Desde Safari, Mail, WhatsApp u otra app: Compartir → **Guardar en DocumentBrain**.
2. La extensión copia los archivos compartidos al inbox del App Group (`group.com.documentbrain.shared`).
3. Al activar DocumentBrain, `SharedInboxImporter` detecta el inbox y lanza el pipeline normal (extracción → chunking → embeddings).

Soporta archivos adjuntos, URLs y texto plano compartido.

---

## Stack tecnológico

| Categoría | Tecnología |
|---|---|
| UI | SwiftUI, NavigationStack, TabView |
| Persistencia | GRDB 6 (SQLite), FTS5 |
| Búsqueda semántica | CoreML, `multi-qa-MiniLM-L6-cos-v1` (384-dim) |
| Tokenización | BERT WordPiece (vocab propio) |
| LLM cloud | Gemini Flash 2.5 vía Cloudflare Worker proxy |
| LLM on-device | Apple Foundation Models (iOS 26+) |
| Extracción de texto | PDFKit, Vision (OCR), ZIPFoundation |
| Sincronización | CloudKit / CKSyncEngine (iOS 17+) |
| Proxy edge | Cloudflare Workers (JavaScript) |
| Mínimo iOS | iOS 16 |

---

## Desarrollo local

### Requisitos

- macOS con Xcode 16+.
- Simulador iOS o dispositivo físico.
- `Config.plist` con las claves de entorno (ver abajo).

### Config.plist

Crea `DocumentBrain/Config.plist` (no incluido en el repo):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>WorkerURL</key>
    <string>https://tu-worker.workers.dev</string>
    <key>AppSecret</key>
    <string>tu-secreto-compartido</string>
</dict>
</plist>
```

### Cloudflare Worker (opcional para desarrollo local)

```bash
cd cloudflare-worker
npm install -g wrangler
wrangler login

# Configurar secretos de producción
wrangler secret put GEMINI_API_KEY
wrangler secret put APP_SECRET

# Desplegar
wrangler deploy
```

### Comandos de build y test

```bash
# Listar esquemas disponibles
xcodebuild -list -project DocumentBrain.xcodeproj

# Ejecutar tests unitarios
xcodebuild test \
  -project DocumentBrain.xcodeproj \
  -scheme DocumentBrain \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.0'
```

---

## Tests

`DocumentBrainTests/` cubre:

- `VectorMathTests`: similitud coseno, norma y operaciones vectoriales.
- `AppDatabaseTests`: migraciones de schema, CRUD de entidades con base de datos en memoria.
- `SearchViewModelTests`: búsqueda con EmbeddingService mockeado (sin cargar CoreML).

La inyección de `EmbeddingServiceProtocol` hace que los tests de ViewModel sean deterministas y rápidos.

---

## Estado del proyecto

El flujo completo está implementado y funcional:

**ingesta → indexado semántico → organización en carpetas → consulta conversacional con citas**

Áreas de mejora identificadas:

- Ajustar pesos del hybrid search (vectorial vs. FTS5) con una colección de test para optimizar recall/precision en colecciones grandes.
- Ampliar cobertura de tests al pipeline completo (extractores por tipo de archivo, chunking edge cases, ranking).
- Resolver warnings de concurrencia de Swift 6 estricto (`Sendable`, actor isolation).
- Explorar re-ranking de resultados (cross-encoder liviano) para mejorar la selección final de chunks antes de pasarlos al LLM.
