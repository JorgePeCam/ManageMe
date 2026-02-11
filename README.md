
Documentación Técnica Detallada: ManageMe (iOS)
Versión de Arquitectura: 2.0 (Sistema RAG Híbrido: Local + Cloud)
1. Resumen de Arquitectura
ManageMe sigue una arquitectura MVVM (Model-View-ViewModel) acoplada a un patrón Repository para la gestión de datos. El núcleo inteligente de la aplicación implementa el patrón RAG (Retrieval-Augmented Generation), que combina búsqueda local ultrarrápida (SQLite FTS5 + CoreML Vectorial) con generación de lenguaje natural en la nube (OpenAI) o localmente (Apple Foundation Models).

2. Capa de Base de Datos y Repositorios
El almacenamiento se gestiona mediante SQLite (utilizando la librería GRDB) para garantizar persistencia y búsquedas complejas.
2.1. AppDatabase (El Motor de SQLite)
Gestiona la creación y migración de las tablas de la base de datos.
Tablas principales creadas:
document: Guarda los metadatos de los archivos (título, fecha, ruta, tamaño).
documentChunk: Guarda el texto extraído dividido en párrafos o "chunks".
chunkVector: Almacena el embedding (vector matemático) en formato .blob asociado a cada chunk.
documentChunk_fts: Tabla virtual generada usando fts5 para indexar todo el texto de los chunks.
Triggers: Crea disparadores (AFTER INSERT, AFTER DELETE, AFTER UPDATE) para asegurar que la tabla de búsqueda rápida FTS5 esté siempre sincronizada con la tabla documentChunk sin intervención manual en código Swift.
2.2. ChunkRepository (Gestor de Búsqueda)
Se encarga de recuperar los trozos de texto para el Chat.
hybridSearch(queryVector: [Float], queryText: String, limit: Int, minScore: Double) async throws -> [SearchResult]: (Función Crítica) Ejecuta una consulta SQL avanzada que puntúa cada fragmento de texto usando dos estrategias simultáneas:
Distancia del coseno entre los vectores (búsqueda por significado).
Coincidencia FTS5 (búsqueda por palabras clave exactas).
Devuelve los fragmentos ordenados por relevancia.

3. Capa de Procesamiento (El "Túnel de Ingesta")
Cuando un usuario añade un archivo, este pasa por una serie de servicios orquestados para "digerirlo" y prepararlo para la IA.
3.1. DocumentProcessor (El Orquestador)
Coordina todo el trabajo en segundo plano para no congelar la App.
process(documentId: String) async:
Llama a TextExtractionService para sacar el texto.
Llama a ChunkingService para partir el texto en párrafos.
Llama a EmbeddingService para convertir cada párrafo en vectores.
Guarda los resultados en la base de datos y marca el documento como .completed.
3.2. TextExtractionService (El Lector)
detectFileType(from url: URL) -> FileType: Averigua si el archivo es un PDF, una imagen, un archivo de texto, Word o Excel basándose en su extensión.
extractText(...): Dependiendo del tipo de archivo, usa PDFDocument (para PDFs), Vision (OCR para imágenes) o decodificadores propios para leer cada letra.
3.3. EmbeddingService (El Traductor Vectorial)
Se comunica con el modelo local MiniLM.mlpackage cargado en CoreML.
init(): Carga el modelo y fuerza su ejecución usando los procesadores locales disponibles (NPU o CPU). Inicializa también el BERTTokenizer usando el diccionario vocab.txt.
generateEmbedding(for text: String) async throws -> [Float]: Envía un texto al tokenizador y luego a la matriz MLMultiArray de CoreML.
extractMeanPooling(hiddenState: MLMultiArray) -> [Float]: Lee la salida de CoreML y extrae los 384 valores numéricos correspondientes al token CLS (el resumen matemático de la frase).

4. Capa de Preguntas y Respuestas (Q&A y LLMs)
Este módulo procesa la conversación con el usuario. Usa un protocolo (QAProvider) para poder tener múltiples "cerebros" intercambiables.
4.1. Protocolo QAProvider
Define las reglas que cualquier modelo de IA debe cumplir para conectarse a la app.
var isAvailable: Bool: Define si el servicio está listo (ej. si la API key está presente o si el dispositivo lo soporta).
answer(query: String, context: [SearchResult]) async throws -> String: Recibe la pregunta y los textos, y devuelve la respuesta.
4.2. OpenAIQAProvider (Implementación Cloud)
Conecta la app con OpenAI usando la API de Chat Completions.
Variables: Usa el modelo gpt-4o-mini por su bajo coste y alta velocidad. Recupera la API Key de UserDefaults.
answer(query:, context:): Construye un objeto JSON con el rol system (reglas base) y el rol user (la pregunta real). Hace una llamada asíncrona mediante URLSession, comprueba códigos de error HTTP 200 y decodifica la respuesta.
4.3. FoundationModelQAProvider (Implementación Local Futura)
Prepara el terreno para iOS 26+ (Apple Intelligence).
isAvailable: Revisa si la clase FoundationModels.SystemLanguageModel existe en el dispositivo. Si es así, la IA correrá en local.
4.4. QAService (El Coordinador de Prompts)
activeProvider: Revisa la lista de proveedores disponibles. Si la IA de Apple está disponible, la usa. Si no, salta a OpenAI.
static buildPrompt(query: String, context: [SearchResult]) -> String: Ensambla el texto final. Inyecta reglas antibullshit ("Solo usa información que aparezca en los fragmentos proporcionados", "Si no está, dilo claramente") e interpola en formato texto plano cada uno de los SearchResult obtenidos de la base de datos.

5. Modelos de Vista (ViewModels)
El puente entre la pantalla gráfica (SwiftUI) y el núcleo de datos.
5.1. LibraryViewModel (Gestión de Documentos)
importFile(from url: URL) async: Inicia la copia segura de un archivo local a la carpeta de la app e inicia su procesado en segundo plano usando Task.detached para aislar el proceso.
importCameraImage(_ image: UIImage) async: Recibe una foto, la comprime a JPEG (.8) y la guarda como si fuera un documento más.
deleteDocument(id: String): Limpia el archivo físico de la memoria del teléfono y ordena al repositorio purgarlo de la base de datos.
5.2. ChatViewModel (Gestión de la Conversación)
La clase más crítica para el usuario final.
sendQuery(): Valida que el texto no esté vacío, lo añade al historial de mensajes de la pantalla y lanza la búsqueda.
search(query: String) async:
Llama a EmbeddingService.generateEmbedding(for: query).
Ejecuta chunkRepo.hybridSearch buscando los top 5 resultados con un minScore de 0.15 (umbral de tolerancia).
Construye objetos de tipo Citation para mostrar al usuario en qué documentos específicos basó la respuesta.
Decide: Si qaService.hasAnyProvider es true, lanza OpenAI. Si es falso, llama a la función de respaldo buildExtractiveAnswer.
buildExtractiveAnswer(from results: [SearchResult], query: String): Muestra en pantalla un aviso amistoso por falta de API Key y vuelca literalmente las líneas de texto donde se encontró la coincidencia.

