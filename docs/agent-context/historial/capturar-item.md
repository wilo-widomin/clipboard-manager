---
dominio: historial
accion: capturar-item
actualizado: 2026-08-02
archivos:
  - Sources/ClipboardManagerKit/Monitor/ClipboardMonitor.swift
  - Sources/ClipboardManagerKit/Models/ClipboardItem.swift
  - Sources/ClipboardManagerKit/Models/ClipboardStore.swift
  - src/ClipboardManager/App/AppDelegate.swift
---

# Capturar un item del portapapeles

Lo copiado por el usuario entra solo: no hay callback de sistema para "clipboard
cambiado", así que se sondea `NSPasteboard.changeCount` una vez por segundo.

## Flujo

1. `AppDelegate` programa un `Timer` de 1 Hz → `ClipboardMonitor.tick()`.
2. `tick()` compara `changeCount`; si no cambió, sale sin leer nada.
3. `readPasteboard()` intenta **imagen primero**, texto después.
4. `imageData()` prueba en orden: PNG crudo → TIFF crudo (a PNG, o el TIFF tal cual si
   la conversión falla) → `NSImage(pasteboard:)` para PDF, file-URLs y tipos prometidos.
5. `ClipboardItem.image(pngData:)` escribe el fichero en `images/<uuid>.png` y guarda
   solo el nombre; `ClipboardItem.text(_:)` guarda el texto ya trimmed.
6. `store.add(_:)` deduplica, aplica el cap del tipo, re-ordena y persiste.

## Reglas

- Imágenes de más de ~10 MB (`maxImageSize`) se descartan enteras.
- El texto se guarda con trim; si queda vacío no se captura.
- La deduplicación compara contenido: texto exacto, o **bytes del PNG leídos del
  disco** en imágenes (`imageBytes`).

## Trampas

- El orden imagen-antes-que-texto importa: muchas apps ponen a la vez una imagen y su
  representación textual, y al revés se guardaría la basura de texto.
- Nunca descartes una imagen porque falle la conversión a PNG: un TIFF de una app Qt
  fallaba `NSBitmapImageRep` → PNG y desaparecía en silencio. Por eso el fallback
  devuelve el TIFF crudo (que `NSImage` pinta igual) pese a que el fichero se llame
  `.png`.
- Pegar desde la app vuelve a escribir en el portapapeles, así que el monitor re-lee
  ese mismo contenido ~1s después: es la vía normal por la que entra un duplicado, y
  el motivo de que `add` herede favorito y grupo.
