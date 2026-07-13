# Clipboard Manager — Visión y Alcance

## Objetivos del negocio

Proporcionar un gestor de portapapeles ligero y siempre accesible desde la barra de menús de macOS que permita:

- Recuperar los últimos 100 elementos copiados (texto e imágenes)
- Mantener elementos favoritos siempre visibles al inicio de la lista
- Organizar los favoritos en grupos y filtrar la lista por grupo
- Navegar entre vista de texto, imágenes y grupos mediante un selector segmentado
- Visualizar imágenes en miniatura y abrirlas en Vista Previa (Quick Look) de macOS
- Pegar cualquier elemento en la app activa con un clic

## In-Scope (lo que el sistema SÍ hará)

| Funcionalidad | Descripción |
|---|---|
| Monitorización de clipboard | Detectar nuevos elementos copiados mediante polling del `changeCount` de `NSPasteboard` cada 1 segundo |
| Captura de texto | Almacenar hasta 100 textos copiados con los primeros 40 caracteres como preview |
| Captura de imágenes | Almacenar hasta 100 imágenes copiadas (límite por tipo, independiente del de texto) con miniatura |
| Lista ordenada | Los items se muestran del más reciente al más antiguo |
| Favoritos | Marcar/desmarcar items como favoritos con icono de estrella. Los favoritos aparecen siempre antes que el resto, ordenados por fecha entre sí |
| Grupos | Asignar un favorito a un grupo (📁). Asignar grupo auto-favorita el item. La vista Grupos permite crear, renombrar y borrar grupos, y filtrar la lista con checkboxes |
| Pegar con un clic | Al clicar un item se copia al portapapeles y se pega (Cmd+V) en la app que estaba activa |
| Eliminación | Botón 🗑 para eliminar un item individual, y botones de cabecera para vaciar los no-favoritos de texto o de imágenes. Sin confirmación (acción directa) |
| Selector de vista | Picker segmentado Texto / Imágenes / Grupos |
| Quick Look de imágenes | El botón 👁 abre la imagen en Quick Look (`qlmanage -p`) sin cerrar el popover |
| Popover redimensionable | El tamaño del popover se puede ajustar por los bordes/esquina y se persiste |
| Persistencia JSON | Los items se guardan en `~/Library/Application Support/ClipboardManager/store.json`; los grupos en `groups.json`; las imágenes como PNG en disco |
| Agente sin Dock | La app corre como `LSUIElement` (sin icono en el Dock) |

## Out-of-Scope (lo que NO hará)

- No sincronizará clipboard entre dispositivos
- No capturará archivos del Finder (solo texto plano e imágenes de clipboard)
- No tendrá búsqueda
- No tendrá atajos de teclado para pegar items específicos
- No tendrá exportación de datos

## Stack tecnológico

- **macOS 13+** (mínimo)
- **Swift 5.9+**
- **AppKit** (`NSStatusItem` + `NSPopover` + `NSHostingController`; un pequeño `NSMenu` nativo solo para el clic derecho: Abrir / About / Quit)
- **SwiftUI** (todo el contenido del popover: filas, selector de vista y gestión de grupos)
- **JSON** (Codable) para persistencia
- **No dependencias externas**
