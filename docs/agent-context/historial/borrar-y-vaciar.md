---
dominio: historial
accion: borrar-y-vaciar
actualizado: 2026-11-21
archivos:
  - Sources/ClipboardManagerKit/Models/ClipboardStore.swift
  - Sources/ClipboardManagerKit/UI/PopoverRootView.swift
---

# Borrar y vaciar

Dos gestos distintos: el 🗑 de una fila borra ese item, y el 🗑 de la cabecera vacía
los **no favoritos** de la vista actual.

## Flujo

1. Fila → `store.remove(id:)`, directo y sin confirmación.
2. Cabecera → `PopoverRootView` pone `confirmClearType` y muestra un `.alert`
   ("¿Borrar textos/imágenes no favoritos?"), que avisa de que los favoritos se
   conservan.
3. Confirmar → `store.clearNonFavorites(ofType:)`.

## Reglas

- `clearNonFavorites(ofType:)` respeta el otro tipo y los favoritos; existe también
  `clearNonFavorites()` (todos los tipos), hoy sin UI que lo invoque.
- Ambas rutas borran del disco los PNG de las imágenes eliminadas.
- Todo pasa por `retire(_:)`: un item que **es o fue favorito** (borrar con 🗑 un
  favorito, o vaciar uno al que se le quitó la estrella) deja un tombstone sin
  contenido en `itemTombstones` (guardado aparte, en `item-tombstones.enc`), para la
  sincronización futura. El historial que
  nunca fue favorito se borra de verdad. En pantalla no cambia nada: el tombstone
  no se enseña nunca (ver «Modelo sincronizable» en `_dominio.md`).
- El botón de cabecera solo aparece en las vistas Texto e Imágenes, no en Grupos.

## Trampas

- El vaciado ignora el filtro de grupo activo: borra los no favoritos del tipo aunque
  la lista muestre un subconjunto. Como los no favoritos nunca tienen grupo, lo que se
  ve filtrado y lo que se borra casi nunca coincide — no lo "arregles" filtrando por
  `visibleItems` sin decidir antes qué se espera.
- Borrar un item **no** toca los grupos; eliminar un grupo tampoco borra items (ver
  `grupos/_dominio.md`).
