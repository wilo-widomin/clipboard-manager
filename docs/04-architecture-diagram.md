# Clipboard Manager — Diagrama de Arquitectura

```mermaid
flowchart TD
    subgraph "Sistema"
        CM[ClipboardManager\nLSUIElement]
    end

    subgraph "Menú (AppKit)"
        SI[StatusItemController\nNSStatusItem]
        MB[MenuBuilder\nNSMenu dinámico]
        TR[TextRowView\nNSView personalizado]
        IR[ImageRowView\nNSView personalizado]
        VS[ViewSelectorView\nSubmenú Text/Images]
    end

    subgraph "Monitorización"
        CMON[ClipboardMonitor\nPolling NSPasteboard\ncada 1s]
    end

    subgraph "Modelo (MVVM)"
        CS[ClipboardStore\nObservableObject]
        CI[(ClipboardItem\nid, date, type,\ntext/image data,\nisFavorite)]
    end

    subgraph "Persistencia"
        JSON[JSONPersistenceService\nstore.json]
    end

    subgraph "Sistema macOS"
        PB[NSPasteboard\ngeneral]
        QL[Vista Previa\nqlmanage -p]
    end

    %% Flujo
    PB -->|changeCount| CMON
    CMON -->|nuevo item| CS
    CS -->|publica items| MB
    MB -->|construye filas| TR
    MB -->|construye filas| IR
    VS -->|selecciona vista| MB
    CS <-->|load/save| JSON
    TR -->|clic imagen| QL

    SI -->|menu delegate| MB
    MB -->|NSMenu| SI
```

## Flujo de datos

```
1. Usuario copia (Cmd+C) → NSPasteboard.changeCount se incrementa
2. ClipboardMonitor detecta el cambio (1s)
3. Lee el contenido del pasteboard
4. Crea ClipboardItem (tipo, datos, timestamp)
5. Lo añade a ClipboardStore
6. ClipboardStore persiste a JSON
7. Siguiente vez que se abre el menú, MenuBuilder lo muestra
8. Si el menú ya está abierto, se refresca inmediatamente
```

## Flujo de vistas

```
Menú principal
├── Submenú "View"
│   ├── "Text" (seleccionado por defecto)
│   └── "Images"
├── Items dinámicos (según vista seleccionada)
│   ├── Texto: TextRowView [30 chars] [⭐] [🗑]
│   └── Imagen: ImageRowView [80×80 thumbnail] [⭐] [🗑]
└── Items fijos
    └── "Quit"
```