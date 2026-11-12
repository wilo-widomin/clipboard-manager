# Blueprint — App Android hermana y sincronización cifrada

> Estado: **diseño**, nada implementado. Decisiones cerradas el 21-08-2026.
> Orden acordado: **la app Android va primero**; el cifrado en reposo de macOS
> puede llegar después, pero **siempre antes del sync**.
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

**Móvil y tablet a la vez.** Son dos aparatos de pleno derecho, no un aparato y su
espejo: el emparejamiento tiene que valer para N y la interfaz necesita layout
adaptativo — en tablet, lista y detalle a la vez; en móvil, uno u otro.

**Desbloqueo**: `BiometricPrompt` con huella, y patrón/PIN del aparato como
alternativa (`DEVICE_CREDENTIAL`). Es el equivalente exacto del
`deviceOwnerAuthentication` de macOS, con la misma ventana de gracia de 15 minutos.

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

## 4. Qué se sincroniza

**Solo los favoritos.** El historial no favorito es ruido en el móvil y se recicla
solo por los topes. Consecuencia que hay que respetar en la interfaz: **quitarle la
estrella a un item lo saca del conjunto sincronizado**, así que desaparece de los
demás aparatos (queda en el que lo tenga localmente hasta que su tope lo recicle).
Los grupos sí viajan enteros: son pocos y dan sentido a los favoritos.

## 5. Claves y cifrado

**No hay contraseña maestra que recordar.** Un borrador anterior de este documento
derivaba la clave de una contraseña inventada para la app; sobra, y confundía dos
cosas distintas:

- **Desbloquear la app** usa la credencial del propio aparato — Touch ID / contraseña
  del Mac, huella / patrón en Android. No es una contraseña de la app, no la
  guardamos y no hay nada que recuperar. Es lo que ya hace `ProtectedAccess`.
- **Cifrar lo que viaja** necesita una clave compartida entre aparatos, y el sistema
  operativo no entrega la contraseña de inicio de sesión para derivarla.

Por eso: `masterKey` (32 bytes) es **aleatoria**, generada una vez en el Mac al
activar el sync. De ella salen por HKDF `recordKey` (cifra registros), `blobKey`
(cifra imágenes) y `blobIdKey`.
- Cifrado **AES-256-GCM** con nonce aleatorio por registro — nativo en las dos
  plataformas (CryptoKit / JCA), sin dependencias exóticas.
- **macOS**: `masterKey` en el Keychain. **Android**: envuelta en el Keystore, con
  `BiometricPrompt` para el desbloqueo diario y la base local en SQLCipher.
- **Emparejar otro aparato** es un QR que transporta la `masterKey` y su token del
  servidor. Vale para N aparatos (móvil y tablet son dos emparejamientos).
- **Recuperación opcional**: exportar una vez la `masterKey` como QR/archivo y
  guardarlo donde guardes tus copias. Si se pierden **todos** los aparatos a la vez,
  lo del servidor es ilegible por diseño; esa exportación es la única red.
- El identificador de una imagen ante el servidor es `HMAC(blobIdKey, sha256(png))`,
  no el hash a secas: el servidor no puede comprobar si tengo una imagen concreta.

**El servidor nunca ve la contraseña ni el contenido.** Ve metadatos mínimos:
`entityId`, `seq`, `updatedAt`, `deviceId`, tamaño.

### Cifrado en reposo (local)

La misma forma en los dos lados, decidida ya para que Android **nazca cifrado** y no
haya que migrarlo luego:

- **AES-256-GCM**, clave **por aparato** guardada en el Keychain (macOS) / Keystore
  (Android). No es la `masterKey` del sync: lo local nunca sale del aparato.
- Se cifra **el texto de los items protegidos**, no el historial entero: cifrar todo
  encarece cada arranque sin proteger nada que no esté ya a la vista en la lista.
- **Se cifra en el borde de la persistencia.** En memoria todo sigue en claro, así
  que buscador, filas y editor no se enteran. Eso protege el archivo —copias de
  seguridad, Time Machine, alguien que se lleve el disco—, **no** a alguien sentado
  delante del aparato desbloqueado con la app abierta.
- En macOS hay **migración** del `store.json` en claro que ya existe, con copia previa.
  En Android no hay ninguna si se hace desde el principio.

## 6. Contrato del servidor

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

## 7. Entornos y despliegue

- **Hermético**: el servidor y dos clientes falsos, sin secretos ni red hacia fuera.
  Ahí se verifica lo determinista: que un borrado no resucite, que un reintento no
  duplique, que dos ediciones concurrentes conserven ambos campos, que el servidor
  no pueda descifrar nada. Es puerta de mezcla.
- **Integrado**: el servicio real bajo el dominio local, con los dispositivos de
  verdad. Cierra el hito, no las historias.
- La documentación de despliegue (levantar, desplegar, revertir) nace en el mismo
  commit que el primer `compose`. Direcciones y nombres de máquina, en el archivo
  local ignorado por git.

## 8. Orden de trabajo

1. **App Android local** — crear item, copiar al portapapeles, favoritos, grupos,
   items protegidos con huella/patrón y buscador. Sin red. Base cifrada desde el
   primer día. Móvil y tablet.
2. **Cifrado en reposo en macOS** — las ~150 líneas de Keychain + AES-GCM y la
   migración del `store.json`.
3. **Modelo sincronizable en el Kit** — `updatedAt` por campo, tombstones,
   `deviceId`, `imageHash`. *No toca la red.*
4. **`clipboard-sync-server`** — los cuatro endpoints y la poda, verificado en
   hermético.
5. **Sync en los dos clientes** — emparejamiento por QR y fusión.

El 2 puede adelantarse o retrasarse, pero **nunca después del 4**: en cuanto salen
bytes del aparato, el cifrado deja de ser opcional.

## 9. Abierto

- Cómo se **capturan imágenes** en Android para el sync: la galería da URIs de
  cualquier tamaño, y los topes de la app de escritorio no están pensados para eso.
- Si el servidor debe **notificar** cambios (push) o basta con sincronizar al abrir
  la app y al guardar. Empezar por lo segundo, que no necesita infraestructura.
