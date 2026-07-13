# Clipboard Manager

Gestor de portapapeles para macOS que vive en la barra de menús. Captura automáticamente los últimos 100 elementos copiados (texto e imágenes), permite marcar favoritos y navegar entre vistas.

## Requisitos

- macOS 13+ (Ventura o superior)
- Xcode 15+ (para compilar)

## Compilar y ejecutar

```bash
# Abrir el proyecto (el .xcodeproj está en la raíz del repo)
open ClipboardManager.xcodeproj

# O compilar desde terminal
xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager build
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
- ✅ Grupos para favoritos: botón 📁 en cada item para asignarlo/reasignarlo, vista
  "Grupos" para crear/renombrar (inline)/eliminar, y checkbox por grupo para filtrar
  qué ítems se muestran en las listas de Texto/Imágenes
- ✅ UI en un popover SwiftUI con pestañas Texto / Imágenes / Grupos
- ✅ Popover redimensionable (arrastra el borde derecho, inferior o la esquina); el
  tamaño se recuerda
- ✅ Click izquierdo en el icono = abre/cierra; clic derecho = menú Abrir / Acerca de / Salir
- ✅ Miniaturas para imágenes + 👁 vista rápida (Quick Look)
- ✅ Click en un item → lo pega en la app donde estabas
- ✅ Persistencia JSON entre reinicios (store.json + groups.json)
- ✅ Sin Dock (LSUIElement), solo icono en barra de menús

## Licencia

Uso privado.