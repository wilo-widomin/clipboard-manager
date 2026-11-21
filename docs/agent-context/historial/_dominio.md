---
dominio: historial
actualizado: 2026-11-21
archivos:
  - Sources/ClipboardManagerKit/Models/ClipboardItem.swift
  - Sources/ClipboardManagerKit/Models/ClipboardStore.swift
  - Sources/ClipboardManagerKit/Monitor/ClipboardMonitor.swift
  - Sources/ClipboardManagerKit/Persistence/JSONPersistenceService.swift
  - Sources/ClipboardManagerKit/Security/FileCipher.swift
  - Sources/ClipboardManagerKit/Security/LocalKey.swift
depende_de: [grupos/_dominio]
---

# Historial

Lista de lo copiado (textos e imágenes), con favoritos, límites por tipo y
persistencia. Es el núcleo: casi cualquier tarea acaba tocando `ClipboardStore`.

## Entidades

- `ClipboardItem` (`Models/ClipboardItem.swift`) — `id`, `contentType` (.text/.image),
  `createdAt`, `textContent` (nil en imágenes **y en los protegidos**; `var`, lo edita
  Willy), `imageFilename` (nombre del PNG, **no** una ruta), `isFavorite`, `groupID?`,
  `detail?`, `title?`, `isProtected`, `sealedText?` (texto protegido cifrado, ver
  [edicion-item](../edicion-item/_dominio.md)). `groupID` y `detail` son opcionales con default para que un `store.json`
  viejo decodifique: **cualquier campo nuevo debe seguir esa regla**.
- `ImageStorage` (mismo archivo) — carpeta `…/ClipboardManager/images`; `delete` exige
  nombre pelado (rechaza `/`, anti-traversal). `write` cifra y escribe, `readData`
  descifra (o devuelve tal cual un PNG en claro aún sin migrar) y `loadImage` lo
  convierte en `NSImage` con una caché en memoria por nombre de archivo.
- Persistencia (`JSONPersistenceService`) — `store.json` y `groups.json` cifrados
  con AES-256-GCM; migra el formato en claro y se bloquea si algo existente no se
  puede leer. El detalle está en [arquitectura](../arquitectura.md#datos-cifrados-en-disco).
- `ClipboardStore` — `@Published items` + `groups`, `viewMode` (persistido en
  UserDefaults), `visibleItems` (filtra por vista, por grupo **y** por el buscador —
  `passes(_:)` = `passesGroupFilter` + `matchesSearch`).

## Invariantes

- Orden fijo: favoritos primero, y dentro de cada bloque por `createdAt` desc
  (`sort`). Toda mutación que altere favoritos o grupos re-ordena.
- Límite **por tipo**, nunca global: 50 textos, 20 imágenes (`maxTextItems` /
  `maxImageItems`). Se aplica también al cargar (`capAllTypes`), para normalizar un
  store que creció con límites anteriores.
- El límite cuenta **solo los no favoritos**: los favoritos son ilimitados (pueden ser
  cientos) y no consumen cupo. Solo se expulsan no favoritos, el más viejo primero.
- Al desaparecer un item de imagen (expulsión, borrado, vaciado, dedupe) se borra su
  PNG del disco. Es la única forma de no dejar basura en `images/`.
- Des-favoritar limpia `groupID` (pertenecer a un grupo implica ser favorito).
- Cada mutación pública persiste; `purge` es la excepción privada (no persiste, lo
  hace quien la llama). Hasta que `load()` o `adoptInitialState` terminan, `persist`
  y `persistGroups` no hacen nada: guardar antes pisaría el archivo con menos items.

- Hay **dos entradas** de items: `add` (lo captura el monitor; deduplica) y `addManual`
  (el modal «Nueva contraseña»; ver [edicion-item](../edicion-item/_dominio.md)). Este
  último nace favorito, protegido si se pide, **no deduplica** y rechaza texto en
  blanco o protegido sin título.

## Acciones documentadas

- [Capturar un item del portapapeles](capturar-item.md)
- [Borrar y vaciar](borrar-y-vaciar.md)

## Trampas

- El cap cuenta **los no favoritos de ese tipo**, no el total. Comparar contra
  `items.count` reintroduce un bug ya sufrido (borraba la imagen recién añadida);
  contar también los favoritos reintroduce el otro: con la lista llena de estrellas
  el cupo quedaba a cero y cada item nuevo se autoexpulsaba al instante.
- Des-favoritar **no** re-aplica el cap: el item pasa a competir por el cupo y caerá
  en el siguiente `add` si es el más viejo. A propósito — quitarle la estrella no debe
  hacerlo desaparecer de golpe delante del usuario.
- La deduplicación de imágenes compara los bytes **descifrados**
  (`ImageStorage.readData`). En disco dos copias de la misma imagen nunca coinciden:
  cada escritura lleva un nonce aleatorio.
- `add` deduplica por contenido y **hereda `isFavorite`, `groupID` y `detail`** del
  duplicado que sustituye. Sin eso, clicar un favorito agrupado (que re-copia y el
  monitor re-lee) le borraba el grupo y la nota escrita en el editor. Un protegido
  también hereda su `sealedText`, y contra un protegido solo se compara con la ventana
  de gracia abierta (sin la llave privada no hay texto que comparar): fuera de ella la
  captura entra como item nuevo.
- Editar texto o detalle **no** cambia `createdAt` ni el orden, a propósito.
- La fila de texto usa `textLine`: texto completo en una línea (espacios colapsados),
  y quien recorta es la vista con `lineLimit(1)` según el ancho real. `textPreview`
  (40 caracteres + "...") sigue existiendo para otros anfitriones. Ninguno de los dos
  sirve para pegar ni comparar.
