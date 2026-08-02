# Clipboard Manager — Visión y Alcance

## Objetivos del negocio

Proporcionar un gestor de portapapeles ligero y siempre accesible desde la barra de menús de macOS que permita:

- Recuperar los últimos elementos copiados (50 textos y 20 imágenes, límite por tipo)
- Mantener elementos favoritos siempre visibles al inicio de la lista
- Organizar los favoritos en grupos y filtrar la lista por grupo
- Navegar entre vista de texto, imágenes y grupos mediante un selector segmentado
- Visualizar imágenes en miniatura y abrirlas en Vista Previa (Quick Look) de macOS
- Pegar cualquier elemento en la app activa con un clic
- Editar el texto capturado y guardar una nota de detalle por elemento

## In-Scope (lo que el sistema SÍ hará)

| Funcionalidad | Descripción |
|---|---|
| Monitorización de clipboard | Detectar nuevos elementos copiados mediante polling del `changeCount` de `NSPasteboard` cada 1 segundo |
| Captura de texto | Almacenar hasta 50 textos copiados con los primeros 40 caracteres como preview |
| Captura de imágenes | Almacenar hasta 20 imágenes copiadas (límite por tipo, independiente del de texto) con miniatura |
| Lista ordenada | Los items se muestran del más reciente al más antiguo, con los favoritos primero y una divisoria marcando el corte |
| Favoritos | Marcar/desmarcar items como favoritos con icono de estrella. Los favoritos aparecen siempre antes que el resto, ordenados por fecha entre sí |
| Grupos | Asignar un favorito a un grupo (📁). Asignar grupo auto-favorita el item. La vista Grupos permite crear, renombrar y borrar grupos, y filtrar la lista con checkboxes |
| Filtro por chips | Encima de las listas, una tira de chips (un grupo cada uno + "Sin grupo") con la misma selección que los checkboxes: sin nada marcado se ve todo; marcando uno o varios, la lista se reduce a esos (OR). Un chip ✕ limpia la selección, que además no se persiste entre arranques |
| Pegar con un clic | Al clicar un item se copia al portapapeles y se pega (Cmd+V) en la app que estaba activa |
| Editor del item | Clic derecho en una fila abre una ventana redimensionable con dos áreas de texto: el texto capturado (editable; en imágenes no aparece) y una nota de detalle libre. Las filas con nota muestran un indicador con la nota como tooltip |
| Eliminación | Botón 🗑 para eliminar un item individual (directo, sin confirmación) y botón de cabecera para vaciar los no-favoritos de la vista actual (con confirmación) |
| Selector de vista | Picker segmentado Texto / Imágenes / Grupos |
| Quick Look de imágenes | El botón 👁 abre la imagen en Quick Look (`qlmanage -p`) sin cerrar el popover |
| Popover redimensionable | El tamaño del popover se puede ajustar por los bordes/esquina y se persiste |
| Persistencia JSON | Los items se guardan en `~/Library/Application Support/ClipboardManager/store.json`; los grupos en `groups.json`; las imágenes como PNG en disco |
| Agente sin Dock | La app corre como `LSUIElement` (sin icono en el Dock) |

> Tanto el texto como la nota de detalle se guardan **en claro** en `store.json`. No
> es un almacén de secretos, y por eso tampoco tiene sentido protegerlo con
> autenticación.

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
