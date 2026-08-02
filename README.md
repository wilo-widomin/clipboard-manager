# Clipboard Manager

Gestor de portapapeles para macOS que vive en la barra de menús. Captura automáticamente los últimos elementos copiados (texto e imágenes), permite marcar favoritos y navegar entre vistas.

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

## Distribuir

```bash
./scripts/build-release.sh          # usa la versión del proyecto
./scripts/build-release.sh 1.0.1    # además marca la versión
```

Genera `dist/ClipboardManager-<versión>.dmg`, firmado con el certificado
"Apple Development" del llavero. **No está notarizado**, así que en el equipo
de destino hay que abrirlo la primera vez con clic derecho → Abrir.

## Estructura del proyecto

```
clipboard-manager/
├── docs/              ← Documentación (visión, arquitectura, US, diagrama)
├── src/               ← Código fuente (Swift/Xcode)
├── scripts/           ← build-release.sh (.dmg firmado)
├── tests/             ← Carpeta de tests (vacía: aún no hay suite)
└── README.md          ← Este archivo
```

## Funcionalidades principales

- ✅ Captura automática de texto e imágenes del portapapeles
- ✅ Hasta 50 textos y 20 imágenes (límite por tipo, no global), ordenados del más
  reciente al más antiguo; al llenarse cae el **no favorito** más antiguo de ese tipo
- ✅ Favoritos (⭐) siempre al principio de la lista, separados del resto por una línea;
  nunca se descartan, así que marcar favoritos puede superar el límite del tipo
- ✅ Grupos para favoritos: botón 📁 en cada item para asignarlo/reasignarlo, vista
  "Grupos" para crear/renombrar (inline)/eliminar, y checkbox por grupo para filtrar
  qué ítems se muestran en las listas de Texto/Imágenes
- ✅ Filtro por grupos como chips sobre las listas: sin nada seleccionado se ve todo,
  y al marcar uno o varios chips (incluido "Sin grupo") la lista se reduce a esos.
  El chip ✕ quita todos los filtros de golpe. La selección no se guarda: cada arranque
  empieza mostrando todo
- ✅ La tira de chips se desplaza con flechas ‹ / › cuando no caben todos; las flechas
  desaparecen cuando ya no queda nada que mostrar hacia ese lado
- ✅ Editor por item: clic derecho en una fila abre una ventana redimensionable donde
  puedes **reescribir el texto copiado** y añadirle una **nota de detalle** (en las
  imágenes solo la nota). Las filas con nota muestran un icono 📝 con la nota como
  tooltip. Todo se guarda en claro en `store.json`, así que no lo uses para secretos
- ✅ UI en un popover SwiftUI con pestañas Texto / Imágenes / Grupos
- ✅ Popover redimensionable (arrastra el borde derecho, inferior o la esquina); el
  tamaño se recuerda
- ✅ Click izquierdo en el icono = abre/cierra; clic derecho = menú Abrir / Acerca de / Salir
- ✅ Miniaturas para imágenes + 👁 vista rápida (Quick Look)
- ✅ Click en un item → lo pega en la app donde estabas
- ✅ Borrar un item es directo (🗑); vaciar de golpe los no favoritos de una vista
  (🗑 de la cabecera) pide confirmación
- ✅ Persistencia JSON entre reinicios (store.json + groups.json)
- ✅ Sin Dock (LSUIElement), solo icono en barra de menús

## Licencia

Uso privado.