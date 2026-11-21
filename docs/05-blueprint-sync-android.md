# Blueprint — Sincronización cifrada entre Mac, Android y Linux

> Estado: §3.1 (archivo cifrado entero) y §3.3 (marca de secreto en el portapapeles) implementados el 21-11-2026, pendientes de probar en el Mac. §6 (modelo sincronizable, sin red: marcas por campo, tombstones, `imageHash`, fusión) y sus vectores del §9 implementados el 21-11-2026, pendientes de que Willy pase `swift test` y lo pruebe en el Mac. El resto, diseño.
> Primera versión cerrada el 21-08-2026; **revisada entera con Willy el 17-11-2026**, pensando solo en la seguridad.
> Los identificadores van en inglés porque acabarán siendo código; la prosa, en castellano.

## 1. Qué se construye

| Pieza | Repo | Qué es |
|---|---|---|
| **Arreglos de seguridad en macOS** | este repo | archivo local cifrado entero, contraseñas que se respetan como secreto, Touch ID que abre la llave de verdad |
| **Modelo sincronizable** | este repo | `ClipboardManagerKit` deja de guardar una foto y pasa a guardar estado con historia suficiente para fusionar aparatos |
| **`clipboard-sync-server`** | repo nuevo | buzón en el Ubuntu de casa; guarda registros cifrados que no puede leer |
| **`clipboard-manager-android`** | repo existente (solo esqueleto) | app Kotlin/Compose con la misma lista, sin captura automática |
| **`clipboard-manager-linux`** | repo nuevo | app de escritorio para el Ubuntu, en Rust |

**Fuera de alcance:**
- **App de terminal.** Se descartó el 17-11-2026. Donde se usaría por SSH es la máquina
  virtual en la que trabajan los agentes, y ahí los agentes tienen permiso de
  administrador sin contraseña (`sudo` y el grupo `docker`): podrían cambiar la app por
  una falsa o leer su memoria mientras está abierta. Además, lo que una contraseña
  imprime dentro de una sesión con un agente entra en la conversación.
- Captura automática del portapapeles en Android (el sistema no la permite fuera de un
  teclado propio), teclado propio, burbuja flotante.
- Compartir con otras personas, multiusuario, Play Store.
- Sincronizar desde fuera de casa (túnel privado): se verá más adelante, ver §8.

## 2. Qué se sincroniza

**Solo los favoritos, más los grupos enteros.** El historial no favorito es ruido fuera
del Mac y se recicla solo por los topes. Consecuencia que la interfaz tiene que dejar
clara: **quitarle la estrella a un item lo saca del conjunto sincronizado** y desaparece
de los demás aparatos (queda en el que lo tenga hasta que su tope lo recicle).

`isFilterEnabled` **no se sincroniza**: es estado de sesión y ni siquiera persiste.

## 3. Arreglos de seguridad en macOS (van primero)

Son fallos de hoy, no de la sincronización. Se hacen antes que todo lo demás.

### 3.1 Archivo local cifrado entero

Hoy `store.json`, `groups.json` y los PNG están en claro en `~/Library/Application
Support/ClipboardManager/`. El historial recoge todo lo que se copia, también
contraseñas copiadas desde otros sitios, y eso acaba en el disco y en Time Machine.

- **Se cifra todo**: `store.json`, `groups.json` y cada imagen. El borrador anterior
  cifraba solo los items protegidos con el argumento de que cifrar todo encarecía el
  arranque; con este volumen cuesta milisegundos.
- **AES-256-GCM** con CryptoKit, nonce aleatorio por escritura.
- **`localKey`**: 32 bytes aleatorios por aparato, en el Keychain con
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. No es la llave del sync: nunca sale
  del aparato. La app la lee al arrancar sin pedir nada, porque tiene que poder
  guardar lo que se copia.
- **Se cifra en el borde de la persistencia** (`JSONPersistenceService`). En memoria
  todo sigue en claro: buscador, filas y editor no se enteran.
- **El formato sigue siendo JSON.** Lo que protege es el cifrado, no el formato. Una
  base de datos solo haría falta si dos programas abrieran el mismo archivo a la vez, y
  no es el caso.
- **Migración** del `store.json` en claro que ya existe: copia previa, cifrado, y
  borrado del archivo en claro solo cuando el cifrado se ha leído bien.

Esto protege el archivo —copias de seguridad, alguien que se lleve el disco—, **no** a
alguien sentado delante del Mac desbloqueado con la app abierta.

### 3.2 Touch ID abre la llave, no solo la pantalla

Hoy `ProtectedAccess` es un control de la app: el texto protegido está disponible y es
la app la que decide no enseñarlo hasta que se pone el dedo. Quien llegue a los datos
por otro camino no pasa por ese control.

- El texto de los items protegidos se cifra **otra vez** con una segunda llave,
  **`protectedKey`**, guardada en el Keychain con `SecAccessControl` de presencia del
  usuario (`.userPresence`: Touch ID o contraseña del Mac). El sistema solo la entrega
  tras autenticar.
- La **ventana de gracia de 15 minutos** se mantiene: la llave descifrada vive en
  memoria ese tiempo y luego se olvida.
- Willy no nota ningún cambio: pide copiar o editar, pone el dedo y funciona igual que
  ahora.
- **Implementado el 21-11-2026, con un recorte que Willy aceptó ese día:** con la firma
  actual (sin perfil de aprovisionamiento) macOS no puede atar la llave a Touch ID, así
  que el dedo lo exige la app, no el sistema. Se gana igualmente que el texto protegido
  no está en claro ni en memoria ni dentro del archivo descifrado. Pasar a que lo exija
  macOS (firmar con perfil y «Keychain Sharing») queda aplazado por decisión de Willy.

### 3.3 Contraseñas copiadas: respetar la marca de secreto

Comprobado en el código el 17-11-2026: `ClipboardMonitor.readPasteboard`
(`ClipboardMonitor.swift`) guarda cualquier texto copiado sin mirar de dónde viene, y
`PasteboardHelper.copyAndPaste` (`PasteboardHelper.swift`) deja el texto pegado en el
portapapeles para siempre.

- **No guardar lo marcado como secreto.** Los gestores de contraseñas (el de Apple,
  1Password, Bitwarden…) marcan lo que copian con los tipos de la convención
  nspasteboard.org: `org.nspasteboard.ConcealedType`, `org.nspasteboard.TransientType`
  y `org.nspasteboard.AutoGeneratedType`. Si aparece alguno, el monitor no lo añade.
- **Marcar lo que pegamos.** Al pegar un item protegido se escribe también
  `org.nspasteboard.ConcealedType` y se prepara con `.currentHostOnly`, para que no
  salte al iPhone o al iPad por el portapapeles compartido de Apple.
- **Borrar a los 30 segundos**, solo si el `changeCount` sigue siendo el nuestro: si
  Willy ha copiado otra cosa en medio, no se toca.
- Hueco que no se puede cerrar: lo copiado desde un sitio que no lo marca (un texto en
  una web o un correo) se guarda como cualquier texto. Ahí protege el §3.1.

## 4. La app Android

- **`createItem`** — escribir un texto o elegir una imagen de la galería, con favorito,
  grupo y nota. Un item creado a mano nace `isFavorite = true`.
- **`copyToClipboard`** — un toque en la fila lo escribe en el portapapeles. Si es
  protegido, con `ClipDescription.EXTRA_IS_SENSITIVE` y borrado a los 30 segundos.
- **`sync`** — contra el servidor de casa.
- **Móvil y tablet** son dos aparatos de pleno derecho: interfaz adaptativa (en tablet,
  lista y detalle a la vez).
- **Desbloqueo** con `BiometricPrompt`: huella, y patrón/PIN como alternativa
  (`DEVICE_CREDENTIAL`). Ventana de gracia de 15 minutos.
- **Nace cifrada**, con la misma forma que el §3: `localKey` en el Keystore (StrongBox
  si el aparato lo tiene) cifra la base entera; `protectedKey` en el Keystore con
  `setUserAuthenticationRequired` cifra además el texto protegido.
- Sin topes por tipo: aquí cada item es deliberado.
- El resto de la interfaz es la de macOS: pestañas Texto / Imágenes / Grupos, favoritos
  arriba con su separador, chips de filtro por grupo, nota por item.

## 5. La app de Linux

- **Rust**, con **Tauri** para la ventana. Instalada en el **Ubuntu de verdad, nunca en
  la máquina virtual de los agentes**.
- Solo crea items, los copia al portapapeles y sincroniza, como Android. No captura el
  portapapeles.
- Guarda igual que el Mac: un archivo cifrado. `localKey` en el llavero del escritorio
  (Secret Service / GNOME Keyring).
- La lógica común (cifrado, fusión, sincronización) va en una librería Rust aparte
  dentro del mismo repo, para que la app sea solo la interfaz.

## 6. Lo que cambia en el modelo (este repo)

`store.json` guarda **el estado final**, sin historia. Dos aparatos que escriben sobre
una foto pierden datos: gana el último que sube, y lo borrado en un sitio resucita
desde otro. Antes de cualquier red hace falta:

- **`updatedAt` por campo mutable**, no por item: `content`, `detail`, `title`,
  `isFavorite`, `isProtected`, `groupID`. Marcar favorito en el móvil mientras se edita
  la nota en el Mac conserva las dos cosas.
- **Marca de origen**: cada cambio lleva `(updatedAt, deviceId)`. `deviceId` desempata
  cuando dos relojes coinciden y hace la fusión determinista.
- **Tombstones**: borrar pone `deletedAt` y conserva el registro.
- **Imágenes por contenido**: `imageFilename` → `imageHash` (SHA-256 del PNG). El
  registro viaja siempre; los bytes, aparte y bajo demanda.
- **Cursor por aparato**: hasta qué `seq` del servidor tiene ya integrado.

Los grupos necesitan lo mismo (`name`, `deletedAt`). `ClipboardStore` sigue siendo la
fuente de verdad; sus mutaciones además **anotan** el cambio.

**Fusión en el cliente:** por cada campo gana el `(updatedAt, deviceId)` mayor;
`deletedAt` gana a cualquier edición. Es last-write-wins por campo, no un CRDT: el único
conflicto real —editar la misma nota en dos sitios a la vez— es rarísimo y perder la
versión más vieja es aceptable.

## 7. Llaves y cifrado del sync

**No hay contraseña maestra que recordar.** Desbloquear la app es siempre la
credencial del aparato (Touch ID, huella, patrón, contraseña del sistema).

### 7.1 La llave compartida

- **`masterKey`** (32 bytes) es aleatoria, se genera una vez en el primer aparato al
  activar el sync y se guarda como la `localKey` de cada plataforma. De ella salen por
  HKDF `recordKey` (registros), `blobKey` (imágenes) y `blobIdKey`.
- **AES-256-GCM**, nonce aleatorio por registro. Nativo en las tres plataformas
  (CryptoKit, JCA, crates de RustCrypto auditados).
- **Cada registro va sellado a su sitio.** El cifrado lleva como dato asociado
  (AAD) `entityType`, `entityId` y la versión del formato. Si el servidor —estropeado o
  manipulado— mueve un registro cifrado de un item a otro, el descifrado falla y el
  cliente lo rechaza.
- El identificador de una imagen ante el servidor es `HMAC(blobIdKey, sha256(png))`:
  el servidor no puede comprobar si tengo una imagen concreta.
- **La `masterKey` nunca aparece en pantalla.** Ni en un QR ni en un código.

### 7.2 Emparejar un aparato nuevo

El borrador anterior mostraba la `masterKey` en un QR: una foto de la pantalla bastaba
para robarla. Ahora se hace como Signal o 1Password:

1. El aparato ya emparejado abre un buzón de emparejamiento en el servidor (caduca en
   pocos minutos) con su llave pública X25519 (A) y enseña un código corto. Willy lo
   teclea en el aparato nuevo.
2. El aparato nuevo genera su par X25519 (B) y un número aleatorio secreto (Nb), y deja
   en el buzón B y un **compromiso**: la huella `SHA-256(B ‖ Nb)`, que fija Nb sin
   enseñarlo.
3. El aparato viejo recoge B y el compromiso, y solo entonces publica su propio número
   aleatorio (Na). Después el nuevo desvela Nb, y el viejo comprueba que corresponde al
   compromiso.
4. Los dos aparatos enseñan un **número de seis cifras** calculado a partir de las dos
   llaves y los dos números (`HKDF(A ‖ B ‖ Na ‖ Nb)`). Willy comprueba que es el mismo y
   confirma en el aparato viejo, que cifra la `masterKey` hacia B y la deja en el buzón.
   El nuevo la recoge junto con su token de servidor.

Si alguien se hubiera metido en medio —también el propio servidor—, los números no
coincidirían. El compromiso es lo que lo garantiza: sin él, quien controla el servidor
podría probar llaves falsas hasta dar con una que diera las mismas seis cifras (en un
millón de intentos le basta); con él, cada lado fija lo suyo antes de ver lo del otro y
le queda **una** oportunidad entre un millón. El servidor obliga a ese orden. El detalle
byte a byte y los vectores de prueba están en el contrato del servidor
(`clipboard-sync-server/docs/api.md`, «Protocolo de los clientes»).

Vale para N aparatos: móvil, tablet, Mac y Ubuntu son emparejamientos independientes.

### 7.3 Dar de baja un aparato

Revocar su token no basta: el aparato seguiría sabiendo descifrarlo todo. Al dar de baja
uno:

1. El servidor deja de aceptar su token.
2. Un aparato que sigue de alta genera una `masterKey` nueva, vuelve a cifrar todos los
   registros y las imágenes, y la reparte a los demás por el mismo mecanismo del §7.2.
3. El aparato que rota vuelve a subir todo con la llave nueva, **también las marcas de
   borrado**, y después pide al servidor `POST /changes/purge` hasta el último `seq` de la
   llave vieja: así no queda nada cifrado con ella.

Con solo favoritos es barato.

### 7.4 Recuperación

Si se pierden **todos** los aparatos a la vez, lo del servidor es ilegible por diseño.
La única red es una copia de la `masterKey`:

- **24 palabras** (lista BIP-39 en castellano) que Willy apunta a mano en una libreta.
- Recomendado: una segunda copia en el llavero de Apple (Contraseñas de iCloud).
- **No se puede exportar como archivo.** Un archivo en Descargas o en un correo lo
  deshace todo.
- Mientras quede un aparato vivo, se pueden generar palabras nuevas; al hacerlo, las
  viejas dejan de valer (implica rotar la llave como en el §7.3).

**El servidor nunca ve contraseñas ni contenido.** Ve lo mínimo: `entityId`, `seq`,
`updatedAt`, `deviceId`, tamaño.

## 8. El servidor

Un buzón tonto y **append-only**. No fusiona: no puede, solo tiene datos cifrados.

```
POST /bootstrap               → da de alta el primer aparato con el código de arranque
POST /changes                 → sube un lote de registros cifrados; el servidor asigna `seq`
GET  /changes?since=N         → devuelve los registros con seq > N, en orden
POST /changes/purge           → tras rotar la llave (§7.3), borra lo que quedó con la vieja
PUT  /blobs/:blobId           → sube los bytes cifrados de una imagen (idempotente)
GET  /blobs/:blobId           → los descarga
POST /pairing                 → abre el buzón de emparejamiento (§7.2), con caducidad
POST /pairing/join            → el aparato nuevo se une: su llave y su compromiso
GET  /pairing/:id             → el viejo consulta el buzón
POST /pairing/:id/nonce       → el viejo publica su número aleatorio
POST /pairing/:id/reveal      → el nuevo desvela el suyo
POST /pairing/:id/approve     → el viejo aprueba y deja la llave cifrada
POST /pairing/:id/claim       → el nuevo sondea y recoge llave y token
DELETE /pairing/:id           → el viejo cancela
GET  /devices                 → lista los aparatos
DELETE /devices/:id           → da de baja un aparato (§7.3); nunca el último de alta
```

El contrato completo, con cada campo y cada error, es `clipboard-sync-server/docs/api.md`.

- **Dónde corre:** un contenedor Docker en el Ubuntu de casa, **no** en la máquina
  virtual de los agentes.
- **Dónde escucha: solo en la red de casa** *(decidido el 17-11-2026)*. Desde internet
  no existe. Fuera de casa cada aparato funciona con su copia y sincroniza al volver al
  wifi. El túnel privado (WireGuard) para sincronizar fuera se valorará más adelante y
  no cambia nada de lo demás.
- **Conexión cifrada** (TLS), aunque sea en casa.
- **Autenticación por token de aparato** (Bearer), emitido al emparejar y revocable de
  uno en uno.
- **Poda**: borra los registros de una `entityId` superados por otro posterior; una
  imagen se borra cuando ninguna entidad viva la referencia.
- **Si se rompe o se borra**, no hay pérdida: cada aparato tiene su copia completa y lo
  vuelve a llenar.
- **Cuándo sincroniza un aparato:** al abrir la app, al guardar un cambio y cada pocos
  minutos mientras está abierta. Sin avisos push: no hacen falta en casa.

## 9. Las mismas reglas en tres lenguajes

Swift, Kotlin y Rust tienen que cifrar, sellar y fusionar exactamente igual. Se fija un
juego de **vectores de prueba compartidos** (entradas y salidas congeladas: llaves,
nonces, registros cifrados, casos de fusión) que los tres pasan en sus tests. Viven en
este repo y los otros dos los copian.

## 10. Entornos y despliegue

- **test**: el servidor y clientes falsos, sin secretos ni red hacia fuera. Ahí se
  verifica lo determinista: que un borrado no resucite, que un reintento no duplique,
  que dos ediciones concurrentes conserven ambos campos, que un registro movido de
  sitio se rechace, que un aparato dado de baja no pueda leer lo nuevo y que el
  servidor no pueda descifrar nada. Sin verde no se mezcla.
- **preproducción**: el servicio real en el Ubuntu de casa, con los aparatos de verdad.
  Lo prueba Willy.
- La documentación de despliegue (levantar, desplegar, revertir) nace en el mismo commit
  que el primer `compose`. Direcciones y nombres de máquina, en el archivo local
  ignorado por git.

## 11. Orden de trabajo

1. **Arreglos de seguridad en macOS** (§3): marca de secreto, archivo cifrado entero
   con migración, Touch ID sobre la llave.
2. **App Android local** (§4) — sin red, cifrada desde el primer día. Móvil y tablet.
3. **Modelo sincronizable en el Kit** (§6) y **vectores de prueba** (§9). No toca la red.
4. **`clipboard-sync-server`** (§8), verificado en test.
5. **Sync en Mac y Android** — emparejamiento (§7.2), fusión, baja (§7.3) y
   recuperación (§7.4).
6. **App de Linux** (§5).

Nada sale de un aparato antes de que el punto 1 esté hecho.

## 12. Abierto

- Cómo se **capturan imágenes** en Android para el sync: la galería da archivos de
  cualquier tamaño, y los topes de la app de escritorio no están pensados para eso.
- Cómo se **desbloquea un item protegido en Linux**: no hay Touch ID. Lo natural es
  pedir la contraseña del usuario de Ubuntu; está por comprobar qué ofrece el
  escritorio para eso.
- Lenguaje del servidor: propuesta Rust, para compartir la librería del §5. Sin decidir.
- Túnel privado para sincronizar fuera de casa.
