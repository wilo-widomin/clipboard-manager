---
dominio: popover
actualizado: 2026-08-02
archivos:
  - src/ClipboardManager/MenuUI/StatusItemController.swift
  - Sources/ClipboardManagerKit/UI/PopoverRootView.swift
  - src/ClipboardManager/MenuUI/AboutView.swift
  - src/ClipboardManager/MenuUI/AboutWindowController.swift
depende_de: [historial/_dominio]
---

# Popover (barra de menús)

Todo lo visible: el `NSStatusItem`, el `NSPopover` que hospeda la UI SwiftUI, el menú
nativo de clic derecho y la ventana About.

## Entidades

- `StatusItemController` — dueño del status item y del popover; guarda el
  `pasteTarget` que captura al abrirlo. **Solo app suelta**: no está en el Kit.
- `PasteTargetTracker` (Kit) — resuelve a qué app hay que pegar y mantiene el
  historial de activaciones (ver [pegar-item](pegar-item.md)).
- `PopoverActions` (Kit) — struct de callbacks (`selectItem`, `quickLook`,
  `editDetail`) que el anfitrión inyecta en las vistas. **Solo** lo que necesita
  AppKit pasa por aquí; las mutaciones de datos van directas al store.
- `PopoverRootView` (Kit) — picker Texto/Imágenes/Grupos, listas, chips y handles de
  resize. Con `ownsWindow: false` no dibuja los handles ni fija tamaño: los pinta
  solo cuando es dueño de la ventana.
- `PopoverSize` — tamaño persistido y acotado (ver [redimensionar](redimensionar.md)).
- Filas: `ClipboardTextRow`, `ClipboardImageRow`, más `DetailIndicator` y el menú 📁.

## Invariantes

- Clic izquierdo en el icono alterna el popover; clic derecho (o ctrl+clic) abre un
  `NSMenu` mínimo: Abrir / About / Quit. Es el único `NSMenu` que queda.
- El popover es `.applicationDefined` y se cierra a mano con un monitor global de
  clics fuera: un `.transient` no puede volverse key en una app LSUIElement inactiva y
  se cerraría al instante.
- `popover.animates = false`: la animación por frame haría que el arrastre de resize
  se sintiera lento.
- Las filas gestionan su propio cursor (`pointingHand`) y su hover.

## Acciones documentadas

- [Pegar un item](pegar-item.md)
- [Redimensionar el popover](redimensionar.md)

## Trampas

- La UI se migró de `NSMenu` a popover porque las vistas dentro de un `NSMenu` en
  tracking no reciben clics, botones ni clic derecho de forma fiable. No vuelvas a
  meter filas interactivas en un `NSMenu`.
- Los 8pt de borde derecho/inferior están **reservados** para los handles de resize: si
  una fila se extiende hasta el borde, los dos hover se pelean por el cursor.
- Quick Look se lanza como proceso externo (`/usr/bin/qlmanage -p`) para no bloquear
  el popover.
