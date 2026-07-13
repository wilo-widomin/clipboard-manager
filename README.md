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
- ✅ Grupos para favoritos: botón 📁 en cada item para asignarlo/reasignarlo,
  vista "Grupos" para crear/renombrar/eliminar, y checkbox por grupo para filtrar
  qué favoritos se muestran en las listas de Texto/Imágenes
- ✅ Vista separada para texto, imágenes y grupos (submenú)
- ✅ Miniaturas de 80×80 para imágenes
- ✅ Click en imagen → abre en Vista Previa de macOS
- ✅ Persistencia JSON entre reinicios
- ✅ Sin Dock (LSUIElement), solo icono en barra de menús

## Licencia

Uso privado.