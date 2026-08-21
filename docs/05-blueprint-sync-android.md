# Blueprint — App Android hermana y sincronización cifrada

> Estado: **diseño**, nada implementado. Decisiones cerradas el 21-08-2026.
> Los identificadores van en inglés porque acabarán siendo código; la prosa, en español.

## 1. Qué se construye (fase 1)

Tres piezas:

| Pieza | Repo | Qué es |
|---|---|---|
| **Modelo sincronizable** | este repo | `ClipboardManagerKit` deja de guardar una foto y pasa a guardar estado con historia suficiente para fusionar dos dispositivos |
| **`clipboard-sync-server`** | repo nuevo | servicio propio en la red de casa; almacén tonto de registros cifrados |
| **`clipboard-manager-android`** | repo nuevo | app Kotlin/Compose con la misma lista, sin captura automática |

**Fuera de alcance en fase 1:** captura automática del portapapeles en Android
(el sistema no la permite fuera de un IME), teclado propio, burbuja flotante,
compartir con terceras personas, publicación en Play Store.

## 2. La app Android, en tres verbos

- **`createItem`** — el usuario escribe un texto o elige una imagen de la galería, con
  favorito, grupo y nota. Es el editor que ya existe en macOS, sin clic derecho.
- **`copyToClipboard`** — un toque en la fila escribe el ítem en el portapapeles del
  sistema. Escribir sí está permitido con la app en primer plano, que es el caso.
  Android 13+ muestra su propio aviso de copiado: no añadimos otro.
- **`sync`** — contra el servicio propio.

El resto de la interfaz es la de macOS: pestañas Texto / Imágenes / Grupos, favoritos
arriba con su separador, chips de filtro por grupo, nota por ítem.

**Sin topes por tipo en Android.** Los topes (50 textos / 20 imágenes) existen porque
en macOS la lista se llena sola; aquí cada ítem es deliberado. Un ítem creado a mano
nace `isFavorite = true`, igual que hoy hace la asignación de grupo.

## 3. Lo que hay que cambiar en este repo

`store.json` guarda **el estado final**, sin historia. Dos dispositivos que escriben
sobre una foto pierden datos siempre: gana el último que sube y lo demás desaparece,
y lo borrado en un sitio resucita desde el otro. Antes de cualquier red hace falta:

- **`updatedAt` por campo mutable**, no por ítem: `content`, `detail`, `isFavorite`,
  `groupID`. Un ítem al que marco favorito en el móvil mientras edito su nota en el
  Mac debe conservar las dos cosas.
- **Marca de origen**: cada cambio lleva `(updatedAt, deviceId)`. `deviceId` es el
  desempate cuando dos relojes coinciden, y hace la fusión determinista.
- **Tombstones**: borrar pone `deletedAt` y conserva el registro. Sin esto, borrar en
  el móvil es un no-cambio que el Mac deshace en el siguiente sync.
- **Imágenes por contenido**: `imageFilename` (nombre local) → `imageHash`
  (SHA-256 del PNG). El registro del ítem viaja siempre; los bytes, aparte y bajo
  demanda. Dos dispositivos con la misma imagen la almacenan una vez.
- **Cursor por dispositivo**: hasta qué `seq` del servidor tengo ya integrado.

`ClipboardStore` sigue siendo la fuente de verdad; lo que cambia es que sus mutaciones
además **anotan** el cambio. Los grupos necesitan lo mismo (`name`, `deletedAt`);
`isFilterEnabled` **no se sincroniza** — es estado de sesión y hoy ni siquiera persiste.

## 4. Contraseña y cifrado

Hoy la nota vive en claro en `store.json`, y por eso se quitó el gate de
autenticación (`docs/agent-context/edicion-item/`). Con datos saliendo del equipo eso
deja de valer:

- `masterKey` (32 bytes) = **Argon2id**(contraseña, salt). De ella salen por HKDF
  `recordKey` (cifra registros), `blobKey` (cifra imágenes) y `blobIdKey`.
- Cifrado **AES-256-GCM** con nonce aleatorio por registro — nativo en las dos
  plataformas (CryptoKit / JCA), sin dependencias exóticas.
- **macOS**: `masterKey` en el Keychain. **Android**: envuelta en el Keystore, con
  `BiometricPrompt` para el desbloqueo diario y la base local en SQLCipher.
- **Emparejar un segundo dispositivo** es un QR que transporta la `masterKey` y el
  token del servidor. No se re-deriva la contraseña en cada aparato.
- El identificador de una imagen ante el servidor es `HMAC(blobIdKey, sha256(png))`,
  no el hash a secas: el servidor no puede comprobar si tengo una imagen concreta.

**El servidor nunca ve la contraseña ni el contenido.** Ve metadatos mínimos:
`entityId`, `seq`, `updatedAt`, `deviceId`, tamaño.

## 5. Contrato del servidor

Un almacén tonto y **append-only**. No fusiona: no puede, solo tiene ciphertext.
La fusión es siempre del cliente.

```
POST /changes          → sube un lote de registros cifrados; el servidor asigna `seq`
GET  /changes?since=N  → devuelve los registros con seq > N, en orden
PUT  /blobs/:blobId    → sube los bytes cifrados de una imagen (idempotente)
GET  /blobs/:blobId    → los descarga
```

- Autenticación por **token de dispositivo** (Bearer), emitido al emparejar y
  revocable de uno en uno.
- El servidor **poda** los registros de una `entityId` superados por otro posterior:
  el log no crece sin fin. Un blob se borra cuando ninguna entidad viva lo referencia.
- Un solo *vault* (el de Willy). Multiusuario no entra en fase 1.

**Fusión en el cliente:** por cada campo, gana el `(updatedAt, deviceId)` mayor;
`deletedAt` gana a cualquier edición. Es last-write-wins por campo, no un CRDT: el
único conflicto real —editar la misma nota en dos sitios a la vez— es rarísimo y
perder la versión más vieja es aceptable. Un CRDT costaría diez veces más.

## 6. Entornos y despliegue

- **Hermético**: el servidor y dos clientes falsos, sin secretos ni red hacia fuera.
  Ahí se verifica lo determinista: que un borrado no resucite, que un reintento no
  duplique, que dos ediciones concurrentes conserven ambos campos, que el servidor
  no pueda descifrar nada. Es puerta de mezcla.
- **Integrado**: el servicio real bajo el dominio local, con los dispositivos de
  verdad. Cierra el hito, no las historias.
- La documentación de despliegue (levantar, desplegar, revertir) nace en el mismo
  commit que el primer `compose`. Direcciones y nombres de máquina, en el archivo
  local ignorado por git.

## 7. Orden de trabajo

1. **Modelo sincronizable en el Kit** — `updatedAt` por campo, tombstones, `deviceId`,
   `imageHash`. Con migración del `store.json` existente. *No toca la red.*
2. **Cifrado local + contraseña maestra en macOS** — y el gate de desbloqueo, que
   ahora sí protege algo.
3. **`clipboard-sync-server`** — los cuatro endpoints y la poda, verificado en
   hermético.
4. **Sync en macOS** — cliente completo contra el servidor.
5. **App Android** — sobre un protocolo ya probado por dos clientes.

Cada paso deja algo usable por sí solo: el 1 y el 2 mejoran la app de macOS aunque
nunca llegue el móvil.

## 8. Abierto

- Qué pasa con los ítems **no favoritos** del Mac: ¿se sincronizan los 50 textos del
  historial o solo favoritos y grupos? Sincronizar todo hace ruido en el móvil.
- Si se pierde la contraseña, los datos del servidor son irrecuperables por diseño.
  ¿Hace falta una vía de recuperación (frase semilla) o basta con que el Mac tenga
  siempre una copia en claro local?
