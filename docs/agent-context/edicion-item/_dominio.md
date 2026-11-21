---
dominio: edicion-item
actualizado: 2026-11-21
archivos:
  - Sources/ClipboardManagerKit/UI/DetailEditorWindowController.swift
  - Sources/ClipboardManagerKit/UI/PasswordCreatorWindowController.swift
  - Sources/ClipboardManagerKit/Security/ProtectedAccess.swift
  - Sources/ClipboardManagerKit/Security/ProtectedKey.swift
  - Sources/ClipboardManagerKit/Security/ProtectedTextCipher.swift
  - Sources/ClipboardManagerKit/Security/PasswordGenerator.swift
  - Sources/ClipboardManagerKit/Models/ClipboardStore.swift
depende_de: [historial/_dominio, popover/_dominio]
---

# Edición de un item

El clic derecho sobre una fila abre una ventana donde se reescribe el **texto
capturado**, se anota un **detalle** libre y se marca el item como **protegido**
(con el **título** que la lista enseñará en su lugar).

## Entidades

- `DetailEditorWindowController` — ciclo de vida de la ventana; se auto-retiene en el
  diccionario estático `open` (id del item → controlador) y se suelta en
  `windowWillClose`. Un item tiene **un solo editor**: abrirlo otra vez trae al frente
  el que hay (`bringToFront`: sale de minimizado, activa la app, `orderFrontRegardless`).
  Las ventanas llevan `tabbingMode = .disallowed`, así que nunca se agrupan en pestañas.
- `DetailEditorView` — dos `TextEditor` (texto y nota) para items de texto, solo la
  nota para imágenes; `canSave` bloquea Guardar si el texto queda en blanco, y
  también si está protegido sin título. Con `isProtected` el texto capturado se
  pinta como contraseña (`SecureField`) y el ojo lo alterna a `TextEditor`; empieza
  siempre tapado aunque ya se haya autenticado. Siembra el texto desde el item que
  recibe (ya revelado), no desde el almacén, donde va cifrado. Si Guardar falla (sin
  llave para cifrar) lo dice en rojo y no cierra.
- **Proteger hace favorito**: cuando `setText` pasa un item de no protegido a protegido,
  lo marca `isFavorite` (con su marca `favorite`) para que el tope del historial no se
  lo lleve. Desproteger no quita la estrella. `addManual` ya nace favorito.
- `ProtectedAccess` — la puerta: `deviceOwnerAuthentication` (Touch ID o contraseña
  del Mac) con **ventana de gracia de 15 minutos** en memoria. `reveal(_:reason:action:)`
  autentica, saca la llave privada del Llavero con el mismo `LAContext` y entrega a
  `action` **una copia** del item con el texto descifrado en `textContent`; lo no
  protegido pasa directo. `run(for:reason:)` sigue existiendo pero no descifra. Al
  caducar la ventana (temporizador con hora real, y comprobación en cada uso) olvida la
  llave privada. Cancelar no avisa; una llave que no aparece o un descifrado que falla
  sí, con un `NSAlert`.
- `ProtectedKey` — la `protectedKey`: par X25519 (la privada son 32 bytes
  aleatorios). Dónde vive cada parte y qué impone el sistema, en
  [arquitectura](../arquitectura.md#texto-protegido-con-su-propia-llave).
- `ProtectedTextCipher` — cifra hacia la pública con una llave efímera (X25519 +
  HKDF-SHA256 + AES-256-GCM) y descifra con la privada. Formato `"CLPP"` + versión +
  pública efímera + `combined`, en base64 dentro de `ClipboardItem.sealedText`.
- `RightClickCatcher` — `NSViewRepresentable` superpuesto a la fila; su `hitTest`
  solo devuelve la vista cuando el evento actual es `.rightMouseDown`, de forma que
  clics izquierdos, botones y hover atraviesan.
- `PasswordCreatorWindowController` / `PasswordCreatorView` — modal «Nueva contraseña»
  (ventana propia, como el editor): título, contraseña (tapada, con ojo), generador,
  detalle, grupo y `Protegida`. Se abre desde el pie de la pestaña Texto y guarda con
  `store.addManual(...)`.
- `PasswordGenerator` — valor puro: largo 8–64, mayúsculas/minúsculas/números/símbolos
  y «símbolos extra» (se suman a los de serie; con «Símbolos» apagado, solo estos).
  Garantiza un carácter de cada categoría activa y usa `SystemRandomNumberGenerator`.
  Los «símbolos extra» se recuerdan entre usos (`@AppStorage`, clave
  `passwordGeneratorExtraSymbols`); el resto de opciones vuelve a su valor por defecto.
- Mutaciones: `store.setText(id:text:isProtected:title:)` (lo que usa el editor:
  texto, protección y título de una vez, con el texto en claro en la mano),
  `store.setDetail(id:detail:)`, y las antiguas `setTextContent(id:text:)` y
  `setProtection(id:isProtected:title:)`, que ahora pasan por `setText`.

## Invariantes

- El texto se guarda **verbatim** (el trim solo sirve para comprobar si está vacío) y
  un texto en blanco se rechaza en las dos capas: botón deshabilitado y guard en el
  store.
- La nota en blanco **sí** es válida: borra el detalle (`nil`).
- Guardar no toca `createdAt` ni el orden de la lista.
- La nota **sobrevive a re-copiar el item**: `ClipboardStore.add` hereda `detail` del
  duplicado que sustituye, igual que el favorito y el grupo.
- Solo los items `.text` tienen editor de contenido **y protección**; una imagen se
  revela en su miniatura, así que esconder su texto no protegería nada.
- Proteger **exige título**: sin él la fila no tendría qué enseñar. Al desproteger,
  el título se conserva por si vuelve a activarse.
- Las dos acciones que **revelan** contenido —pegar y abrir el editor— pasan por
  `ProtectedAccess.reveal`. Favorito, grupo y borrar no enseñan nada y van directas.
- La ventana de gracia vive solo en memoria: al reabrir la app siempre pregunta.
- **Un item protegido nunca tiene el texto en claro en el almacén**: `textContent =
  nil` y el texto en `sealedText`. Solo las copias que entrega `reveal` lo llevan en
  claro (al pegar y en el editor abierto). Al desproteger, `setText` lo vuelve a
  guardar en claro y borra `sealedText`.
- **Proteger no pide autenticación**: cifrar usa la llave pública. Tampoco crear una
  contraseña protegida ni la migración. Solo pide el dedo **ver** el texto.
- **Sin llave no se guarda**: si la pública no se puede obtener, `setText` devuelve
  `false` y `addManual` `nil` sin tocar nada; nunca se guarda en claro un texto que se
  pidió proteger. `setProtection(…, false, …)` necesita la privada en memoria (ventana
  abierta); sin ella devuelve `false`.
- **Migración**: al cargar, un item protegido de una versión anterior (texto en claro,
  sin `sealedText`) se cifra en memoria y se guarda con un solo `persist()` atómico. Si
  la llave no se puede obtener, se deja como estaba (protegido en la interfaz, como
  antes) y se reintenta en el siguiente arranque; mientras, `reveal` lo entrega tal cual.
- La `protectedKey` se crea **la primera vez que hace falta cifrar**: al proteger el
  primer item, al crear la primera contraseña protegida o en la migración. Crearla no
  pide nada.
- `DetailIndicator` (glifo `note.text`) aparece en la fila cuando `hasDetail`, con la
  nota como tooltip.

- Un item creado a mano (`addManual`) nace **favorito** —si no, el tope de 50 textos
  lo borraría— y **no pasa por la deduplicación** de `add`. Se rechaza sin contraseña
  o, si va protegido, sin título. No tiene estado propio: es un item de texto normal.

## Trampas

- Reabrir el editor de un item protegido sigue pasando por `ProtectedAccess.reveal`
  (dentro de la ventana de gracia no pide el dedo); si el editor ya estaba abierto, solo
  se trae al frente y no se reemplaza su contenido.

- La ventana es propia, no una sheet ni una vista dentro del popover: al tomar el foco,
  cerraría el popover (que se cierra con el monitor global de clic-fuera).
- **Si Touch ID lo impone macOS o la app depende de la firma.** Con la firma de hoy
  (sin perfil de aprovisionamiento) la llave privada está en el llavero de sesión y es
  la app quien pide el dedo antes de leerla; el sistema solo impone lo mismo que con la
  `localKey`. Ver [arquitectura](../arquitectura.md#texto-protegido-con-su-propia-llave).
- La **nota** (`detail`) y el **título** de un item protegido no van cifrados con la
  `protectedKey`, solo con la `localKey` como el resto del archivo: el buscador los
  necesita.
- Pegar un item protegido lo marca como oculto en el portapapeles, así que el monitor
  no lo vuelve a capturar. Si Willy copia el mismo texto desde otro sitio con la
  ventana cerrada, entra como item nuevo del historial (no se puede comparar sin la
  llave).
- El tooltip de la nota (`DetailIndicator`) **no** se enseña en un item protegido:
  el candado no valdría de nada si el globo de ayuda cantara la nota.
- El editor se abre vía `PopoverActions.editDetail` (necesita AppKit), pero el guardado
  va directo al store.
- Editar el texto puede dejar dos items con el mismo contenido: la deduplicación solo
  actúa al capturar, no al editar.
- Borrar a mano del Llavero los elementos `com.widomin.clipboard-manager.protected-key`
  deja ilegibles para siempre los textos protegidos: la app no crea otra llave mientras
  quede alguno cifrado, ni cifra nada nuevo hacia una pública cuya privada no encuentra.
