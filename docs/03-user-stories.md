# Clipboard Manager — User Stories

## Priorización (MoSCoW)

### Must Have (imprescindible para MVP)

| ID | Historia | Criterios de aceptación |
|---|---|---|
| US-01 | Como usuario, quiero que la app esté en la barra de menús para acceder rápidamente | Icono persistente en NSStatusBar. Al clicar, se abre el menú |
| US-02 | Como usuario, quiero que se capture automáticamente el texto que copio | Al copiar texto (Cmd+C), aparece en la lista en <2s. Máximo 100 items |
| US-03 | Como usuario, quiero ver los últimos 30 caracteres de cada texto copiado | Cada item de texto muestra una línea con los primeros 30 caracteres. Si es más largo, truncado con "…" |
| US-04 | Como usuario, quiero eliminar items de la lista | Cada item tiene un botón 🗑 que lo elimina sin confirmación. Desaparece al instante |
| US-05 | Como usuario, quiero marcar items como favoritos | Cada item tiene un botón ⭐ que lo marca/desmarca como favorito |
| US-06 | Como usuario, quiero que los favoritos aparezcan siempre primero | Los items con `isFavorite = true` se muestran antes que los no favoritos, ordenados por fecha descendente |
| US-07 | Como usuario, quiero cambiar entre ver texto e imágenes | Submenú "View" con entradas "Text" e "Images". Al seleccionar, se muestra la lista correspondiente |

### Should Have

| ID | Historia | Criterios de aceptación |
|---|---|---|
| US-08 | Como usuario, quiero que las imágenes copiadas se capturen automáticamente | Al copiar una imagen, aparece en la vista de imágenes con miniatura 80×80 |
| US-09 | Como usuario, quiero clicar una imagen para abrirla en Vista Previa | Al clicar la miniatura, se abre `qlmanage -p` con la imagen. El menú no se cierra |
| US-10 | Como usuario, quiero que los datos persistan entre reinicios | Al cerrar y abrir la app, los items (incluyendo favoritos) se restauran |

### Could Have

| ID | Historia | Criterios de aceptación |
|---|---|---|
| US-11 | Como usuario, quiero un indicador visual de cuántos items hay (texto + imágenes) | En el icono de la barra o en el menú, mostrar contador "24 text · 8 images" |

### Won't Have (para esta versión)

| ID | Historia |
|---|---|
| US-12 | Sincronización entre dispositivos |
| US-13 | Búsqueda en la lista |
| US-14 | Atajos de teclado para pegar items específicos |