---
dominio: popover
accion: pegar-item
actualizado: 2026-08-02
archivos:
  - src/ClipboardManager/MenuUI/StatusItemController.swift
  - Sources/ClipboardManagerKit/UI/PasteboardHelper.swift
depende_de: [historial/_dominio]
---

# Pegar un item

Clicar una fila copia su contenido al portapapeles y lo pega en la app donde estaba
el usuario. Es el flujo más frágil de la app: depende del foco y de permisos.

## Flujo

1. **Antes** de mostrar el popover, `showPopover` captura el destino con
   `resolvePasteTarget()` — la app frontmost que no seamos nosotros, o la última vista
   en `focusHistory` (hasta 8, alimentada por `didActivateApplicationNotification`).
2. Clic en la fila → `PopoverActions.selectItem` → `StatusItemController.selectItem`,
   que cierra el popover y llama a `PasteboardHelper.copyAndPaste(...)`.
3. El helper escribe en `NSPasteboard.general`, reactiva la app destino y, tras
   `pasteDelay` (0.25s), postea `Cmd+V` como evento CG.

## Reglas

- Texto: `setString`. Imagen: se carga del disco (`item.loadImage()`) y se escribe con
  `writeObjects`.
- Sin permiso de **Accesibilidad** el `Cmd+V` se descarta en silencio: `postCmdV`
  comprueba `AXIsProcessTrusted()` y, si falta, lanza el prompt del sistema y aborta.

## Trampas

- El orden capturar-destino → activar-nos es obligatorio: mostrar el popover activa
  nuestra app, así que después ya no se sabe dónde había que pegar.
- La app se activa a propósito (`NSApp.activate`) porque en una app LSUIElement
  inactiva los controles del popover no responden al clic.
- El retardo de 0.25s no es adorno: con 0.15s la reactivación aún no había surtido
  efecto y el pegado se perdía. Si tocas ese valor, pruébalo con apps lentas de
  activar.
- Pegar vuelve a escribir en el portapapeles, así que el monitor re-lee ese contenido
  al segundo siguiente: el `add` deduplicado es lo que evita el doble item.
