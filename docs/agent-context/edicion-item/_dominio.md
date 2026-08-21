---
dominio: edicion-item
actualizado: 2026-08-21
archivos:
  - Sources/ClipboardManagerKit/UI/DetailEditorWindowController.swift
  - Sources/ClipboardManagerKit/Security/ProtectedAccess.swift
  - Sources/ClipboardManagerKit/Models/ClipboardStore.swift
depende_de: [historial/_dominio, popover/_dominio]
---

# Edición de un item

El clic derecho sobre una fila abre una ventana donde se reescribe el **texto
capturado**, se anota un **detalle** libre y se marca el item como **protegido**
(con el **título** que la lista enseñará en su lugar).

## Entidades

- `DetailEditorWindowController` — ciclo de vida de la ventana; se auto-retiene en el
  array estático `open` y se suelta en `windowWillClose`.
- `DetailEditorView` — dos `TextEditor` (texto y nota) para items de texto, solo la
  nota para imágenes; `canSave` bloquea Guardar si el texto queda en blanco, y
  también si está protegido sin título. Con `isProtected` el texto capturado se
  pinta como contraseña (`SecureField`) y el ojo lo alterna a `TextEditor`; empieza
  siempre tapado aunque ya se haya autenticado.
- `ProtectedAccess` — la puerta: `deviceOwnerAuthentication` (Touch ID o contraseña
  del Mac) con **ventana de gracia de 15 minutos** en memoria. `run(for:reason:)`
  deja pasar directo lo no protegido.
- `RightClickCatcher` — `NSViewRepresentable` superpuesto a la fila; su `hitTest`
  solo devuelve la vista cuando el evento actual es `.rightMouseDown`, de forma que
  clics izquierdos, botones y hover atraviesan.
- Mutaciones: `store.setTextContent(id:text:)`, `store.setDetail(id:detail:)` y
  `store.setProtection(id:isProtected:title:)`.

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
  `ProtectedAccess`. Favorito, grupo y borrar no enseñan nada y van directas.
- La ventana de gracia vive solo en memoria: al reabrir la app siempre pregunta.
- `DetailIndicator` (glifo `note.text`) aparece en la fila cuando `hasDetail`, con la
  nota como tooltip.

## Trampas

- La ventana es propia, no una sheet ni una vista dentro del popover: al tomar el foco,
  cerraría el popover (que se cierra con el monitor global de clic-fuera).
- **La autenticación esconde, no cifra.** El texto de un item protegido sigue en
  claro en `store.json`: quien abra el archivo lo lee sin pasar por Touch ID. Por eso
  se quitó una primera versión del gate; ahora vuelve porque el usuario lo pidió
  explícitamente para ocultar contenido a quien mire la pantalla. Cifrarlo en disco
  es el paso siguiente (`docs/05-blueprint-sync-android.md`).
- El tooltip de la nota (`DetailIndicator`) **no** se enseña en un item protegido:
  el candado no valdría de nada si el globo de ayuda cantara la nota.
- El editor se abre vía `PopoverActions.editDetail` (necesita AppKit), pero el guardado
  va directo al store.
- Editar el texto puede dejar dos items con el mismo contenido: la deduplicación solo
  actúa al capturar, no al editar.
