# Clipboard Manager — User Stories

## Priorización (MoSCoW)

### Must Have (imprescindible para MVP)

| ID | Historia | Criterios de aceptación |
|---|---|---|
| US-01 | Como usuario, quiero que la app esté en la barra de menús para acceder rápidamente | Icono persistente en `NSStatusBar`. Clic izquierdo abre/cierra el popover; clic derecho muestra un menú nativo (Abrir / About / Quit) |
| US-02 | Como usuario, quiero que se capture automáticamente el texto que copio | Al copiar texto (Cmd+C), aparece en la lista en <2s. Máximo 50 items de texto |
| US-03 | Como usuario, quiero ver los primeros caracteres de cada texto copiado | Cada item de texto muestra los primeros 40 caracteres. Si es más largo, se trunca con "..." |
| US-04 | Como usuario, quiero eliminar items de la lista | Cada item tiene un botón 🗑 que lo elimina sin confirmación. Desaparece al instante. El 🗑 de la cabecera vacía los no-favoritos de la vista actual, previa confirmación que avisa de que los favoritos se conservan |
| US-05 | Como usuario, quiero marcar items como favoritos | Cada item tiene un botón ⭐ que lo marca/desmarca como favorito |
| US-06 | Como usuario, quiero que los favoritos aparezcan siempre primero | Los items con `isFavorite = true` se muestran antes que los no favoritos, ordenados por fecha descendente, con una divisoria marcando el corte |
| US-07 | Como usuario, quiero cambiar entre ver texto, imágenes y grupos | Picker segmentado "Texto / Imágenes / Grupos". Al seleccionar, se muestra la vista correspondiente |
| US-08 | Como usuario, quiero pegar un item en la app activa con un clic | Al clicar un item, su contenido se copia al portapapeles y se pega (Cmd+V) en la app que estaba en primer plano |

### Should Have

| ID | Historia | Criterios de aceptación |
|---|---|---|
| US-09 | Como usuario, quiero que las imágenes copiadas se capturen automáticamente | Al copiar una imagen, aparece en la vista de imágenes con miniatura. Máximo 20 imágenes (límite independiente del de texto) |
| US-10 | Como usuario, quiero previsualizar una imagen en grande | El botón 👁 abre la imagen en Quick Look (`qlmanage -p`). El popover no se cierra |
| US-11 | Como usuario, quiero que los datos persistan entre reinicios | Al cerrar y abrir la app, los items (incluyendo favoritos y grupos) se restauran |
| US-12 | Como usuario, quiero organizar mis favoritos en grupos | El botón 📁 de cada fila asigna el item a un grupo, "Sin grupo" o "Nuevo grupo…". Asignar grupo auto-favorita el item |
| US-13 | Como usuario, quiero gestionar y filtrar por grupos | La vista Grupos permite crear, renombrar (inline) y borrar grupos. Cada checkbox filtra qué items aparecen en las listas de texto/imágenes. Borrar un grupo conserva sus items (solo pierden el grupo) |
| US-14 | Como usuario, quiero filtrar por grupo sin salir de la lista | Sobre las listas hay un chip por grupo más "Sin grupo". Sin nada marcado se ve todo; marcando uno o varios, la lista queda reducida a esos (OR). El chip ✕ limpia la selección, que no se conserva entre arranques |
| US-15 | Como usuario, quiero llegar a todos los chips aunque no quepan | Cuando la tira desborda aparecen flechas ‹ / › que la desplazan; cada flecha se oculta al agotarse ese lado y ambas desaparecen si todos los chips caben |
| US-16 | Como usuario, quiero anotar un item con información extra | Clic derecho en la fila abre un editor en su propia ventana con un área para la nota. Las filas con nota muestran un indicador con la nota como tooltip. Guardar una nota vacía la borra. La nota se guarda en claro, no es para secretos |
| US-17 | Como usuario, quiero corregir el texto que copié | El mismo editor incluye, para los items de texto, un área multilínea con el contenido capturado. Al guardar, la lista y el pegado usan el texto nuevo; la fecha y la posición no cambian. Dejarlo vacío no se permite (Guardar deshabilitado). En imágenes esa área no aparece |

### Could Have

| ID | Historia | Criterios de aceptación |
|---|---|---|
| US-18 | Como usuario, quiero redimensionar el popover a mi gusto | El popover se ajusta arrastrando el borde derecho (ancho), el inferior (alto) o la esquina (ambos). El tamaño se persiste y se recorta a lo que quepa en la pantalla del icono |

### Won't Have (para esta versión)

| ID | Historia |
|---|---|
| US-19 | Sincronización entre dispositivos |
| US-20 | Búsqueda en la lista |
| US-21 | Atajos de teclado para pegar items específicos |
