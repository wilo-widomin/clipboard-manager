---
dominio: historial
actualizado: 2026-08-02
archivos:
  - src/ClipboardManager/Models/ClipboardItem.swift
  - src/ClipboardManager/Models/ClipboardStore.swift
  - src/ClipboardManager/Monitor/ClipboardMonitor.swift
  - src/ClipboardManager/Persistence/JSONPersistenceService.swift
depende_de: [grupos/_dominio]
---

# Historial

Lista de lo copiado (textos e imágenes), con favoritos, límites por tipo y
persistencia. Es el núcleo: casi cualquier tarea acaba tocando `ClipboardStore`.

## Entidades

- `ClipboardItem` (`Models/ClipboardItem.swift`) — `id`, `contentType` (.text/.image),
  `createdAt`, `textContent` (nil en imágenes; `var`, lo edita el usuario),
  `imageFilename` (nombre del PNG, **no** una ruta), `isFavorite`, `groupID?`,
  `detail?`. `groupID` y `detail` son opcionales con default para que un `store.json`
  viejo decodifique: **cualquier campo nuevo debe seguir esa regla**.
- `ImageStorage` (mismo archivo) — carpeta `…/ClipboardManager/images`; `delete` exige
  nombre pelado (rechaza `/`, anti-traversal).
- `ClipboardStore` — `@Published items` + `groups`, `viewMode` (persistido en
  UserDefaults), `visibleItems` (filtra por vista **y** por grupo).

## Invariantes

- Orden fijo: favoritos primero, y dentro de cada bloque por `createdAt` desc
  (`sort`). Toda mutación que altere favoritos o grupos re-ordena.
- Límite **por tipo**, nunca global: 50 textos, 20 imágenes (`maxTextItems` /
  `maxImageItems`). Se aplica también al cargar (`capAllTypes`), para normalizar un
  store que creció con límites anteriores.
- Solo se expulsan **no favoritos**: un tipo puede superar su límite a base de estrellas.
- Al desaparecer un item de imagen (expulsión, borrado, vaciado, dedupe) se borra su
  PNG del disco. Es la única forma de no dejar basura en `images/`.
- Des-favoritar limpia `groupID` (pertenecer a un grupo implica ser favorito).
- Cada mutación pública persiste; `purge` es la excepción privada (no persiste, lo
  hace quien la llama).

## Acciones documentadas

- [Capturar un item del portapapeles](capturar-item.md)
- [Borrar y vaciar](borrar-y-vaciar.md)

## Trampas

- El cap cuenta **items de ese tipo**, no el total. Comparar contra `items.count`
  reintroduce un bug ya sufrido: borraba la imagen recién añadida.
- `add` deduplica por contenido y **hereda `isFavorite` y `groupID`** del duplicado
  que sustituye. Sin eso, clicar un favorito agrupado (que re-copia y el monitor
  re-lee) le borraba el grupo.
- Editar texto o detalle **no** cambia `createdAt` ni el orden, a propósito.
- `textPreview` recorta a 40 caracteres y hace trim: es solo para la fila, nunca para
  pegar ni comparar.
