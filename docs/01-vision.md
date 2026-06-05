# Clipboard Manager — Visión y Alcance

## Objetivos del negocio

Proporcionar un gestor de portapapeles ligero y永久 accesible desde la barra de menús de macOS que permita:

- Recuperar los últimos 100 elementos copiados (texto e imágenes)
- Mantener elementos favoritos siempre visibles al inicio de la lista
- Navegar entre vista de texto y vista de imágenes mediante un submenú
- Visualizar imágenes en miniatura y abrirlas en la aplicación Vista Previa de macOS

## In-Scope (lo que el sistema SÍ hará)

| Funcionalidad | Descripción |
|---|---|
| Monitorización de clipboard | Detectar nuevos elementos copiados mediante polling del `changeCount` de `NSPasteboard` cada 1 segundo |
| Captura de texto | Almacenar hasta 100 textos copiados con los primeros 30 caracteres como preview |
| Captura de imágenes | Almacenar hasta 100 imágenes copiadas con miniatura de 80×80px |
| Lista ordenada | Los items se muestran del más reciente al más antiguo |
| Favoritos | Marcar/desmarcar items como favoritos con icono de estrella. Los favoritos aparecen siempre antes que el resto, ordenados por fecha entre sí |
| Eliminación | Botón para eliminar un item individual. Sin confirmación (acción directa) |
| Submenú Texto/Imágenes | Menú con dos entradas para cambiar entre vista de texto y vista de imágenes |
| Preview de imágenes | Al clicar una imagen, se abre en Vista Previa (Quick Look / `qlmanage`) sin cerrar el menú |
| Persistencia JSON | Los items se guardan en `~/Library/Application Support/ClipboardManager/store.json` |
| Arranque automático | La app se lanza al iniciar sesión (LSUIElement, sin Dock) |

## Out-of-Scope (lo que NO hará)

- No sincronizará clipboard entre dispositivos
- No capturará archivos del Finder (solo texto plano e imágenes de clipboard)
- No tendrá búsqueda
- No tendrá atajos de teclado para pegar items específicos
- No tendrá categorías ni etiquetas
- No tendrá exportación de datos

## Stack tecnológico

- **macOS 13+** (mínimo)
- **Swift 5.9+**
- **AppKit** (NSStatusItem, NSMenu, NSMenuItem.view)
- **SwiftUI** (formularios y submenú de selección de vista)
- **JSON** (Codable) para persistencia
- **No dependencias externas**