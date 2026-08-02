---
dominio: popover
accion: redimensionar
actualizado: 2026-08-02
archivos:
  - Sources/ClipboardManagerKit/UI/PopoverRootView.swift
  - src/ClipboardManager/MenuUI/StatusItemController.swift
---

# Redimensionar el popover

El popover se ajusta arrastrando su borde derecho (ancho), el inferior (alto) o la
esquina (ambos), y el tamaño se recuerda.

## Flujo

1. `PopoverRootView` reserva 8pt (`edge`) a derecha y abajo, y superpone tres zonas
   invisibles: `rightResizeHandle`, `bottomResizeHandle`, `cornerResizeHandle` (16pt).
2. El `DragGesture` actualiza el `@State size` acotado por `PopoverSize.clampWidth` /
   `clampHeight`; al soltar, `PopoverSize.save(_:)` escribe en UserDefaults.
3. `NSHostingController.sizingOptions = [.preferredContentSize]` hace que el cambio de
   `.frame` del contenido redimensione el `NSPopover` de verdad.
4. Al aparecer, y al cambiar la configuración de pantallas
   (`didChangeScreenParametersNotification`), se re-lee `PopoverSize.saved()`.

## Reglas

- Límites: ancho 300–760pt, alto mínimo 260pt; el techo real lo pone la pantalla
  (`limits()`, `visibleFrame` menos 24pt de margen). El alto no tiene tope fijo.
- `StatusItemController.showPopover` fija `PopoverSize.activeScreen` con la pantalla
  del icono **antes** de mostrar.

## Trampas

- `NSScreen.main` sigue a la ventana key: en una app LSUIElement aún inactiva puede
  apuntar a otro monitor, por eso existe `activeScreen`.
- macOS recorta en silencio un popover más grande que el área visible; en pantallas
  bajas eso se comía la cabecera y el picker. Todo tamaño que se entregue debe pasar
  por el clamp.
- Re-clampar al aparecer no pierde el tamaño del usuario: `saved()` relee el valor
  persistido y solo lo capa a lo que quepa ahora.
- Los cursores de resize se ponen con `.onContinuousHover`; el diagonal no existe como
  API pública antes de macOS 15 y se obtiene con un selector privado protegido por
  comprobación en runtime (`Cursors.resizeNWSE`), con `resizeUpDown` de reserva.
