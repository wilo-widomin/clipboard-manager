---
dominio: grupos
accion: asignar-grupo
actualizado: 2026-08-02
archivos:
  - src/ClipboardManager/MenuUI/PopoverRootView.swift
  - src/ClipboardManager/Models/ClipboardStore.swift
depende_de: [historial/_dominio]
---

# Asignar y gestionar grupos

Dos entradas a lo mismo: el botón 📁 de cada fila (asignar) y la pestaña **Grupos**
(crear, renombrar, borrar).

## Flujo

1. 📁 en una fila → `GroupAssignmentMenu` (`PopoverRootView.swift:565`) lista los
   grupos, "Sin grupo" y "Nuevo grupo…".
2. Elegir grupo → `store.assignGroup(itemID:groupID:)`; "Sin grupo" pasa `nil`.
3. "Nuevo grupo…" → `startNewGroup(assignTo:)` guarda el item en `newGroupAssignTo` y
   abre el `.alert` compartido; `createGroup()` crea y **auto-asigna**.
4. Pestaña Grupos → `GroupsManageView` / `GroupManageRow`: renombrado **inline**
   (`TextField` + `.onSubmit` → `renameGroup`), borrado (`deleteGroup`) y botón
   "Nuevo grupo" (mismo alert, sin item asociado).

## Archivos

- `MenuUI/PopoverRootView.swift` — `GroupAssignmentMenu`, `GroupsManageView`,
  `GroupManageRow`, y el `.alert` "Nuevo grupo" que vive en `PopoverRootView`.
- `Models/ClipboardStore.swift` — `addGroup`, `renameGroup`, `deleteGroup`,
  `assignGroup`.

## Reglas

- El icono 📁 se pinta relleno y en color de acento cuando el item tiene grupo.
- Renombrar solo se confirma con Enter; salir del campo sin `onSubmit` no guarda.
- El trash de un grupo avisa en su tooltip de que los items se conservan.

## Trampas

- El alert de "Nuevo grupo" es **uno solo** para los dos orígenes; lo que distingue
  el caso es `newGroupAssignTo`, y hay que dejarlo en `nil` al terminar o el siguiente
  grupo creado desde la pestaña se asignaría al item anterior.
- El clic derecho sobre una fila **no** abre menú de grupos: está tomado por el editor
  del item (ver `edicion-item/_dominio.md`). Ese menú contextual se intentó y no
  funcionaba dentro de un `NSMenu`; el botón 📁 lo sustituye.
