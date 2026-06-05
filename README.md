# Clipboard Manager

Gestor de portapapeles para macOS que vive en la barra de menús. Captura automáticamente los últimos 100 elementos copiados (texto e imágenes), permite marcar favoritos y navegar entre vistas.

## Requisitos

- macOS 13+ (Ventura o superior)
- Xcode 15+ (para compilar)

## Compilar y ejecutar

```bash
# Abrir el proyecto
open src/ClipboardManager/ClipboardManager.xcodeproj

# O compilar desde terminal
xcodebuild -project src/ClipboardManager/ClipboardManager.xcodeproj \
  -scheme ClipboardManager build
```

## Estructura del proyecto

```
clipboard-manager/
├── docs/              ← Documentación
├── src/               ← Código fuente (Swift/Xcode)
├── tests/             ← Tests unitarios
└── README.md          ← Este archivo
```

## Funcionalidades principales

- ✅ Captura automática de texto e imágenes del portapapeles
- ✅ Hasta 100 items, ordenados del más reciente al más antiguo
- ✅ Favoritos (⭐) siempre al principio de la lista
- ✅ Vista separada para texto e imágenes (submenú)
- ✅ Miniaturas de 80×80 para imágenes
- ✅ Click en imagen → abre en Vista Previa de macOS
- ✅ Persistencia JSON entre reinicios
- ✅ Sin Dock (LSUIElement), solo icono en barra de menús

## Licencia

Uso privado.