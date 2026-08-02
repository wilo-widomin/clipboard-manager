---
dominio: grupos
accion: filtrar-por-grupo
actualizado: 2026-08-02
archivos:
  - Sources/ClipboardManagerKit/UI/PopoverRootView.swift
  - Sources/ClipboardManagerKit/Models/ClipboardStore.swift
---

# Filtrar por grupo

El filtro se comporta como un juego de **chips OR**: nada seleccionado = se ve todo.
Dos UIs comparten exactamente la misma selección.

## Flujo

1. Selección = `isFilterEnabled` de cada grupo + `store.showUngrouped`.
2. La cambian los chips (`GroupFilterBadges`, `PopoverRootView.swift:378`) o los
   checkboxes de la pestaña Grupos → `toggleGroupFilter` / `showUngrouped.toggle()`.
3. `isGroupFilterActive` decide si hay filtro; `passesGroupFilter(_:)` decide item a
   item. Las listas de Texto e Imágenes lo aplican al construirse.
4. El chip ✕ (solo visible con filtro activo) → `clearGroupFilter()`.

## Reglas

- Filtro inactivo → pasan todos. Activo → pasa el item cuyo grupo esté seleccionado, o
  el item sin grupo si "Sin grupo" lo está.
- Se aplica a **todos** los items, no solo a los agrupados.
- Con la lista vacía se distingue "Sin textos" de "Sin textos visibles (filtrados)".

## Trampas

- La tira de chips no usa `ScrollView`: se maqueta a su ancho intrínseco
  (`fixedSize`) dentro de un `GeometryReader`, se desplaza con un `offset` y se
  recorta. Las flechas `‹`/`›` pasan ~80% del ancho visible y se ocultan al agotarse
  su lado (`canScrollLeft` / `canScrollRight`); ambas desaparecen si todo cabe
  (`overflows`).
- `clipped()` **no** recorta el hit-testing: sin el `contentShape(Rectangle())` que
  sigue al clip, los chips fuera de vista se comen los clics de la flecha izquierda.
  Los chevrones llevan además `zIndex(1)`.
- El ancho del contenido llega por `ContentWidthKey` (una `PreferenceKey` privada) y
  el `offset` se re-clampa cuando el contenido o el popover cambian de tamaño; si no,
  la tira se queda desplazada más allá del final al borrar un grupo.
- `GroupFilterBadges` necesita altura fija (30pt) o se come el espacio vertical de la
  lista.
