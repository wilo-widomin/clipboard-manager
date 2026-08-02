---
dominio: popover
accion: pegar-item
actualizado: 2026-08-02
archivos:
  - src/ClipboardManager/MenuUI/StatusItemController.swift
  - Sources/ClipboardManagerKit/UI/PasteboardHelper.swift
  - Sources/ClipboardManagerKit/UI/PasteTargetTracker.swift
depende_de: [historial/_dominio]
---

# Pegar un item

Clicar una fila copia su contenido al portapapeles y lo pega en la app donde estaba
el usuario. Es el flujo más frágil de la app: depende del foco y de permisos.

## Flujo

1. **Antes** de mostrar el popover, `showPopover` captura el destino con
   `PasteTargetTracker.resolve()`.
2. Clic en la fila → `PopoverActions.selectItem` → `StatusItemController.selectItem`,
   que cierra el popover y llama a `PasteboardHelper.copyAndPaste(...)`.
3. El helper escribe en `NSPasteboard.general`, reactiva la app destino, **espera a
   que esa app sea realmente la frontmost** y entonces postea `Cmd+V` como evento CG.

## Resolver el destino

`PasteTargetTracker` (en el Kit, porque todo anfitrión del popover tiene el mismo
problema) prueba tres estrategias en orden:

1. **Foco real vía Accesibilidad** — `kAXFocusedApplicationAttribute` sobre el
   elemento system-wide. Es la que acierta cuando el usuario clica el icono desde un
   monitor o escritorio sin ventanas: ahí la app *frontmost* es el Finder (el
   escritorio) y pegar acabaría activando el Finder. No pide permiso nuevo: postear
   el `Cmd+V` sintético ya exige Accesibilidad, así que cuando el pegado puede
   funcionar, esta consulta también.
2. **Frontmost** que no seamos nosotros.
3. **Última activación** vista en el historial (hasta 8, alimentado por
   `didActivateApplicationNotification`).

## Esperar el foco, no adivinarlo

`PasteboardHelper` sondea cada `pollInterval` (0,05 s) hasta que el destino es
frontmost, espera `settleDelay` (0,15 s) para que tenga ventana key, y pega. Si en
`maxWait` (2 s) no llega, pega igual.

El sondeo no es un lujo: cuánto tarda la reactivación varía en dos órdenes de
magnitud. En el mismo escritorio es casi instantánea; si la app vive en otro Space,
macOS reproduce antes la animación de cambio de escritorio. Un retardo fijo lo
bastante largo para el segundo caso haría que el primero pareciese roto — y el
retardo fijo que había (0,25 s) era tan corto que **pegar entre Spaces o entre
monitores fallaba siempre**.

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
- Si tocas los tiempos, prueba **entre monitores y entre Spaces**, no solo en el
  escritorio actual: es donde este flujo se rompe primero.
- Pegar vuelve a escribir en el portapapeles, así que el monitor re-lee ese contenido
  al segundo siguiente: el `add` deduplicado es lo que evita el doble item.
