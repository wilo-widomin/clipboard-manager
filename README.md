# Clipboard Manager

Gestor de portapapeles para macOS que vive en la barra de menús. Captura automáticamente los últimos elementos copiados (texto e imágenes), permite marcar favoritos y navegar entre vistas.

## Requisitos

- macOS 13+ (Ventura o superior)
- Xcode 15+ (para compilar)

## Compilar y ejecutar

Con Xcode instalado, Willy compila con el script de la sección siguiente. Para
desarrollar:

```bash
# Abrir el proyecto (el .xcodeproj está en la raíz del repo)
open ClipboardManager.xcodeproj

# O compilar desde terminal
xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager build
```

## Tests

```bash
swift test
```

Corre el target `ClipboardManagerKitTests` de SwiftPM (`Tests/ClipboardManagerKitTests/`):
los vectores de fusión de `Tests/vectors/merge-vectors.json` y las marcas y
tombstones del store. El proyecto de Xcode no ve estos tests.

## Distribuir

```bash
./scripts/build-release.sh          # usa la versión del proyecto
./scripts/build-release.sh 1.0.1    # además marca la versión
```

Willy compila con este script, que necesita Xcode instalado. Genera
`dist/ClipboardManager-<versión>.dmg`, firmado con el certificado
"Apple Development" del llavero. **No está notarizado**, así que en el equipo
de destino hay que abrirlo la primera vez con clic derecho → Abrir.

## Estructura del proyecto

```
clipboard-manager/
├── docs/              ← Documentación (visión, arquitectura, US, diagrama, plan de sync)
├── Sources/           ← ClipboardManagerKit: el código compartido (paquete SwiftPM)
├── src/               ← La app de barra de menús (Swift/Xcode)
├── scripts/           ← build-release.sh (.dmg firmado)
├── Tests/             ← Tests del paquete (`swift test`) y vectores de fusión
└── README.md          ← Este archivo
```

## Funcionalidades principales

- ✅ Captura automática de texto e imágenes del portapapeles
- ✅ Historial de hasta 50 textos y 20 imágenes (límite por tipo, no global), ordenado
  del más reciente al más antiguo; al llenarse cae el más antiguo de ese tipo
- ✅ Favoritos (⭐) **ilimitados**: no cuentan para el límite ni se descartan nunca, así
  que puedes guardar cientos sin comerte el historial reciente
- ✅ La lista va partida en dos zonas con scroll independiente, separadas por una línea:
  arriba los favoritos (hasta 15 filas de alto, sin pasar de la mitad del popover) y
  debajo el historial hasta el borde inferior
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
  imágenes solo la nota). Cada item tiene su propia ventana: si ya está abierta, vuelve
  al frente. Guardar cualquier cambio real (texto, nota, título o protección) lo marca
  como favorito. Las filas con nota muestran un icono 📝 con la nota como tooltip
- ✅ Buscador sobre las listas: filtra por el texto, el título y la nota, sin distinguir
  mayúsculas ni acentos. No se guarda entre arranques
- ✅ Items protegidos (solo texto): en la lista se ve un título con un candado en lugar
  del contenido, y para pegarlos o abrir su editor pide Touch ID o la contraseña del
  Mac (sin volver a preguntar durante 15 minutos). Su texto va cifrado con una llave
  propia. Hoy quien exige Touch ID es la app, no macOS: eso queda pendiente de firmar
  con un perfil de aprovisionamiento. Al pegar uno, se marca como oculto, no sale del
  Mac y el portapapeles se vacía a los 30 segundos
- ✅ Datos cifrados en disco: `store.enc`, `groups.enc`, las imágenes y los archivos de
  tombstones van cifrados con AES-256-GCM; la clave vive en el Llavero de macOS. Las
  copias de Time Machine anteriores al 21-11-2026 aún guardan el historial en claro
- ✅ No guarda lo secreto: ignora lo que un gestor de contraseñas marca como secreto y
  lo copiado mientras uno (Acceso a Llaveros, Contraseñas, 1Password, Bitwarden…) está
  al frente
- ✅ Contraseñas creadas a mano: el botón «+ Nueva contraseña» al pie de la pestaña
  Texto abre un modal con título, contraseña, detalle, grupo y «Protegida». Incluye un
  generador (largo de 8 a 64, mayúsculas, minúsculas, números, símbolos y símbolos
  extra, que se recuerdan). Se guarda como favorito, así que el límite no la borra
- ✅ UI en un popover SwiftUI con pestañas Texto / Imágenes / Grupos
- ✅ Popover redimensionable (arrastra el borde derecho, inferior o la esquina); el
  tamaño se recuerda
- ✅ Click izquierdo en el icono = abre/cierra; clic derecho = menú Abrir / Acerca de / Salir
- ✅ Miniaturas para imágenes + 👁 vista rápida (Quick Look)
- ✅ Click en un item → lo pega en la app donde estabas
- ✅ Borrar un item es directo (🗑); vaciar de golpe los no favoritos de una vista
  (🗑 de la cabecera) pide confirmación
- ✅ Persistencia JSON entre reinicios (store.enc + groups.enc, cifrados)
- ✅ Sin Dock (LSUIElement), solo icono en barra de menús

## Sincronización

El modelo ya está preparado (marcas por campo, tombstones y `SyncMerge`), pero
todavía no hay red: nada sale del Mac. El plan está en
`docs/05-blueprint-sync-android.md`.

## Proyectos hermanos

- [clipboard-manager-android](https://github.com/wilo-widomin/clipboard-manager-android):
  la app de Android, local y cifrada.
- [clipboard-sync-server](https://github.com/wilo-widomin/clipboard-sync-server): el
  servidor de sincronización en casa; aún no está desplegado.

## Licencia

Uso privado.