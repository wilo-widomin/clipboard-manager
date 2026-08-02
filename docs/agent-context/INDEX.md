# Contexto del proyecto — Clipboard Manager

App de barra de menús para macOS (AppKit + SwiftUI, sin dependencias) que guarda el
historial del portapapeles: textos e imágenes, favoritos, grupos y notas por item.

Lee primero el dominio que corresponda a la tarea. No explores el código sin
haber mirado su documento.

| Si la tarea trata de… | Abre |
|---|---|
| capturar lo copiado, monitor, duplicados, límites, favoritos, orden, borrar, vaciar, persistencia de items | `historial/` |
| grupos, carpetas, asignar, renombrar, filtro, chips/badges, "Sin grupo", flechas de la tira | `grupos/` |
| icono de la barra, popover, pestañas Texto/Imágenes/Grupos, filas, pegar, Cmd+V, foco, Quick Look, tamaño, cursores, About | `popover/` |
| clic derecho en una fila, editar el texto copiado, nota de detalle, ventana del editor | `edicion-item/` |

Transversal:
- `arquitectura.md` — stack, capas, arranque, build/dmg, dónde viven los datos.

## Mapa rápido

El código compartido vive en el paquete **ClipboardManagerKit**; la app suelta es la
cáscara. Hay **una sola copia de cada archivo**: el target de la app compila
`Sources/ClipboardManagerKit/` directamente y Widomin consume ese mismo directorio
como dependencia SPM. Si un segundo anfitrión lo necesitaría, va al paquete.

- `Sources/ClipboardManagerKit/Models/` — `ClipboardItem`, `ClipboardGroup`, `ClipboardStore`
- `Sources/ClipboardManagerKit/Monitor/` — polling del portapapeles
- `Sources/ClipboardManagerKit/Persistence/` — JSON (`store.json` + `groups.json`)
- `Sources/ClipboardManagerKit/UI/` — popover, filas, chips, editor, `PopoverActions`
- `src/ClipboardManager/App/` — entry point (`AppDelegate`), Info.plist, versión
- `src/ClipboardManager/MenuUI/` — status item (foco/pegado) y About: **solo** app suelta
- `docs/01..04-*.md` — documentación de producto (visión, ADD, user stories, diagrama)
- `scripts/build-release.sh` — `.dmg` firmado sin notarizar

`ClipboardStore` es la fuente de verdad: casi cualquier cambio de datos pasa por ahí.
