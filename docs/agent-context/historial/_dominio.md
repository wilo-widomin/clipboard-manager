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
  - Sources/ClipboardManagerKit/Sync/SyncStamp.swift
  - Sources/ClipboardManagerKit/Sync/SyncMerge.swift
  - Sources/ClipboardManagerKit/Sync/DeviceIdentity.swift
  - Tests/ClipboardManagerKitTests/SyncMergeVectorTests.swift
  - Tests/ClipboardManagerKitTests/ClipboardStoreSyncTests.swift
  - Tests/vectors/merge-vectors.json
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
  [edicion-item](../edicion-item/_dominio.md)), y los del modelo sincronizable:
  `imageHash?`, `stamps` y `deletion?` (ver «Modelo sincronizable» abajo). Todos los
  campos añadidos son opcionales o con default y se leen con `decodeIfPresent`, para
  que un `store.json` viejo decodifique: **cualquier campo nuevo debe seguir esa regla**.
  `id` y `createdAt` son `public internal(set) var`: solo el paquete los cambia.
- `ImageStorage` (mismo archivo) — carpeta `…/ClipboardManager/images`; `delete` exige
  nombre pelado (rechaza `/`, anti-traversal). `write` cifra y escribe, `readData`
  descifra (o devuelve tal cual un PNG en claro aún sin migrar) y `loadImage` lo
  convierte en `NSImage` con una caché en memoria por nombre de archivo.
- Persistencia (`JSONPersistenceService`) — `store.enc` y `groups.enc` cifrados
  con AES-256-GCM; funde en ellos un `store.json`/`groups.json` antiguo (en claro o no) y se bloquea si algo existente no se
  puede leer. El detalle está en [arquitectura](../arquitectura.md#datos-cifrados-en-disco).
- `ClipboardStore` — `@Published items` + `groups` (solo lo vivo),
  `itemTombstones` + `groupTombstones` (lo borrado), `deviceId`, `viewMode` (persistido en
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
  PNG del disco. Es la única forma de no dejar basura en `images/`. Un tombstone no
  conserva la imagen.
- Des-favoritar limpia `groupID` (pertenecer a un grupo implica ser favorito).
- Cada mutación pública persiste; `purge` es la excepción privada (no persiste, lo
  hace quien la llama). Hasta que `load()` o `adoptInitialState` terminan, `persist`
  y `persistGroups` no hacen nada: guardar antes pisaría el archivo con menos items.
  Con la persistencia bloqueada (`isPersistenceBlocked`, que lee `blockingError` del
  protocolo) tampoco guardan, y `add`, `addManual` y `addGroup` no hacen nada.

- Hay **dos entradas** de items: `add` (lo captura el monitor; deduplica) y `addManual`
  (el modal «Nueva contraseña»; ver [edicion-item](../edicion-item/_dominio.md)). Este
  último nace favorito, protegido si se pide, **no deduplica** y rechaza texto en
  blanco o protegido sin título.

## Modelo sincronizable (§6 del blueprint)

El modelo local ya guarda lo que la sincronización necesitará; no hay red ni nada
que lo use todavía salvo los tests.

- **`deviceId`** (`Sync/DeviceIdentity.swift`): UUID aleatorio en el archivo
  `device-id`, en claro, junto a `store.enc`. No en `UserDefaults`: la app suelta y
  Widomin comparten la carpeta pero no las preferencias, y escriben el mismo
  historial. `ClipboardStore(persistence:deviceId:)` lo acepta fijo (tests); si no,
  lo lee la primera vez que hace falta una marca.
- **Marcas por campo** (`SyncStamp`, `ItemFieldStamps`): `(updatedAt, deviceId)` para
  `content` (`textContent` + `sealedText`, un solo campo), `detail`, `title`,
  `favorite`, `protection` y `group`; en grupos, `nameStamp`. `updatedAt` va en
  milisegundos enteros. Cada mutación del store marca **solo los campos que cambian
  de verdad** (`toggleFavorite`, `setText`/`setTextContent`, `setDetail`,
  `assignGroup`, `deleteGroup` en los items del grupo, `renameGroup`). Un item nuevo
  nace sin marcas.
- **Marca ausente = implícita, calculada al vuelo, nunca escrita al cargar**: en un
  item, `(createdAt, "")`; en un grupo, `(1-1-1970, "")` (`SyncStamp.legacyGroup`),
  porque los grupos no tienen fecha de creación y la hora de carga cambiaría en cada
  arranque. El `deviceId` vacío pierde ante cualquier aparato real.
  `effectiveStamps()` las rellena.
- **Tombstones**: quitar un item que **es o fue favorito** (`leavesTombstone`: favorito,
  o con marca `favorite`) deja `item.tombstone(stamp)` en `itemTombstones`: solo `id`,
  `contentType`, `createdAt` y `deletion`, sin texto, nota, título ni imagen. Vale para
  `remove`, el tope (`cap`) y los vaciados, todo por `retire(_:)`. El historial que
  nunca fue favorito se borra de verdad, como siempre. Borrar un grupo siempre deja
  tombstone (todos los grupos se sincronizan).
- **Los tombstones no están en `items` ni en `groups`**: viven aparte y solo se juntan
  al guardar (`persist` escribe `items + itemTombstones`). `adoptInitialState` y
  `load()` los vuelven a separar; si un `id` está vivo y borrado, gana el borrado.
  Por eso vistas, recuentos, topes, buscador, deduplicación y filtro de grupos no los
  ven sin tener que filtrar nada.
- **Quitar la estrella**: el item sigue en el historial como no favorito, con su marca
  `favorite` (`hasLeftSyncedSet`). Para los demás aparatos eso es «ha salido del
  conjunto»: la fusión les lleva `isFavorite = false` y cada uno decidirá qué hace
  (propuesta: el Mac lo deja en su historial; un aparato sin historial lo esconde). Cuando el tope lo
  recicla aquí, deja tombstone, para que una estrella vieja de otro aparato no lo
  resucite. Volver a ponerle la estrella antes gana, por ser más reciente.
- **Deduplicar conserva el registro**: la captura que sustituye a un duplicado hereda
  su `id` y sus marcas (fijadas antes con `effectiveStamps()`, porque `createdAt`
  cambia). Pegar un favorito no lo convierte en un borrado más uno nuevo.
- **`imageHash`**: SHA-256 en hexadecimal de los bytes en claro del PNG. Lo calcula
  `ClipboardItem.image(pngData:)` (solo si el archivo se escribió) y, para las
  imágenes antiguas, `fillMissingImageHashes()` al capturar la siguiente imagen, que
  reutiliza la caché `imageDigests`. `imageFilename` sigue siendo el archivo local.
- **Fusión** (`Sync/SyncMerge.swift`): funciones puras `merge(local:remote:)` para
  items y grupos, sueltos o en listas. Por campo gana la marca mayor (fecha y, si
  empata, `deviceId` byte a byte); con marcas idénticas, `local`; `deletion` gana a
  todo. El resultado lleva todas las marcas explícitas; `createdAt` es la mayor;
  `imageFilename` e `isFilterEnabled` son los locales. Las listas salen ordenadas por
  `id`. **No la llama nadie**: la fijan los vectores de `Tests/vectors/merge-vectors.json`,
  que Kotlin y Rust copiarán (§9), y `swift test` los pasa.
- **Poda de tombstones (sin hacer)**: hoy crecen sin límite (unos 150 bytes por
  favorito o grupo borrado). Regla propuesta para cuando haya sincronización: un tombstone se
  puede borrar cuando **todos** los aparatos de alta han integrado el cambio (su
  cursor de servidor ha pasado el `seq` del borrado); como red, a los 90 días aunque
  algún aparato no haya vuelto, y ese aparato, al volver, deberá descargar el estado
  entero en vez de solo los cambios. No se poda contra un servidor que no existe.

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
- `add` deduplica por contenido y **hereda `id`, marcas, `isFavorite`, `groupID` y
  `detail`** del duplicado que sustituye. Sin eso, clicar un favorito agrupado (que re-copia y el
  monitor re-lee) le borraba el grupo y la nota escrita en el editor. Un protegido
  también hereda su `sealedText`, y contra un protegido solo se compara con la ventana
  de gracia abierta (sin la llave privada no hay texto que comparar): fuera de ella la
  captura entra como item nuevo.
- Editar texto o detalle **no** cambia `createdAt` ni el orden, a propósito.
- **Abrir `store.enc` con una versión anterior** (sin modelo sincronizable): los
  tombstones aparecen como filas vacías no favoritas, que su tope recicla. No se
  pierde nada real; la versión anterior simplemente no sabe que estaban borrados.
- **Proteger y editar a la vez en dos aparatos** puede fusionar `isProtected = true`
  con un `textContent` en claro: `adoptInitialState` lo cifra al cargar (la misma
  migración de siempre). Lo contrario, un `sealedText` sin protección, queda para
  cuando se decida cómo viaja el texto protegido (ver `arquitectura.md`).
- La fila de texto usa `textLine`: texto completo en una línea (espacios colapsados),
  y quien recorta es la vista con `lineLimit(1)` según el ancho real. `textPreview`
  (40 caracteres + "...") sigue existiendo para otros anfitriones. Ninguno de los dos
  sirve para pegar ni comparar.
