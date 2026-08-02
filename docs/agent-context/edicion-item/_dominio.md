---
dominio: edicion-item
actualizado: 2026-08-02
archivos:
  - Sources/ClipboardManagerKit/UI/DetailEditorWindowController.swift
  - Sources/ClipboardManagerKit/Models/ClipboardStore.swift
depende_de: [historial/_dominio, popover/_dominio]
---

# Edición de un item

El clic derecho sobre una fila abre una ventana donde se reescribe el **texto
capturado** y se anota un **detalle** libre.

## Entidades

- `DetailEditorWindowController` — ciclo de vida de la ventana; se auto-retiene en el
  array estático `open` y se suelta en `windowWillClose`.
- `DetailEditorView` — dos `TextEditor` (texto y nota) para items de texto, solo la
  nota para imágenes; `canSave` bloquea Guardar si el texto queda en blanco.
- `RightClickCatcher` — `NSViewRepresentable` superpuesto a la fila; su `hitTest`
  solo devuelve la vista cuando el evento actual es `.rightMouseDown`, de forma que
  clics izquierdos, botones y hover atraviesan.
- Mutaciones: `store.setTextContent(id:text:)` y `store.setDetail(id:detail:)`.

## Invariantes

- El texto se guarda **verbatim** (el trim solo sirve para comprobar si está vacío) y
  un texto en blanco se rechaza en las dos capas: botón deshabilitado y guard en el
  store.
- La nota en blanco **sí** es válida: borra el detalle (`nil`).
- Guardar no toca `createdAt` ni el orden de la lista.
- Solo los items `.text` tienen editor de contenido; en imágenes esa sección no se
  monta.
- `DetailIndicator` (glifo `note.text`) aparece en la fila cuando `hasDetail`, con la
  nota como tooltip.

## Trampas

- La ventana es propia, no una sheet ni una vista dentro del popover: al tomar el foco,
  cerraría el popover (que se cierra con el monitor global de clic-fuera).
- **No hay autenticación**, y no debe reintroducirse tal cual: una versión anterior
  pedía Touch ID / contraseña con `LocalAuthentication`, pero el contenido se guarda en
  claro en `store.json`, así que el diálogo solo añadía fricción. Poner una barrera
  exige cifrar la nota o llevarla al Keychain.
- El editor se abre vía `PopoverActions.editDetail` (necesita AppKit), pero el guardado
  va directo al store.
- Editar el texto puede dejar dos items con el mismo contenido: la deduplicación solo
  actúa al capturar, no al editar.
