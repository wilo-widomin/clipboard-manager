# Clipboard Manager — Diagrama de Arquitectura

```mermaid
flowchart TD
    subgraph "App"
        AD[AppDelegate\n@main · LSUIElement]
    end

    subgraph "UI (AppKit + SwiftUI)"
        SI[StatusItemController\nNSStatusItem + NSPopover]
        RM[NSMenu clic-derecho\nAbrir / About / Quit]
        PR[PopoverRootView\nSwiftUI]
        ROWS[Filas Texto/Imagen\n+ vista Grupos]
    end

    subgraph "Monitorización"
        CMON[ClipboardMonitor\nPolling NSPasteboard\ncada 1s]
    end

    subgraph "Modelo (MVVM)"
        CS[ClipboardStore\nObservableObject]
        CI[(ClipboardItem\nid, date, type,\ntext / imageFilename,\nisFavorite, groupID)]
        CG[(ClipboardGroup\nid, name, filtro)]
    end

    subgraph "Persistencia"
        JSON[JSONPersistenceService\nstore.json + groups.json]
        PNG[(Imágenes PNG\nen disco)]
    end

    subgraph "Sistema macOS"
        PB[NSPasteboard\ngeneral]
        QL[Quick Look\nqlmanage -p]
        TGT[App activa\nCmd+V]
    end

    %% Flujo de captura
    PB -->|changeCount| CMON
    CMON -->|nuevo item| CS
    CS <-->|load/save| JSON
    CS -->|imágenes| PNG

    %% Flujo de UI
    CS -->|publica items/grupos| PR
    PR --> ROWS
    SI -->|hospeda| PR
    SI -->|clic derecho| RM

    %% Acciones
    ROWS -->|clic imagen 👁| QL
    ROWS -->|clic item| TGT
```

## Flujo de datos

```
1. Usuario copia (Cmd+C) → NSPasteboard.changeCount se incrementa
2. ClipboardMonitor detecta el cambio (~1s) y lee el contenido
3. Crea ClipboardItem (tipo, texto o PNG en disco, timestamp)
4. Lo añade a ClipboardStore (deduplica y aplica el límite por tipo)
5. ClipboardStore persiste a store.json (y groups.json / PNG según toque)
6. El popover SwiftUI observa el store y se repinta automáticamente
```

## Flujo de vistas

```
Popover (NSPopover + SwiftUI)
├── Picker segmentado: Texto · Imágenes · Grupos
├── Vista Texto    → filas [preview 40 chars] [📁] [⭐] [🗑]
├── Vista Imágenes → filas [miniatura] [👁] [📁] [⭐] [🗑]
└── Vista Grupos   → crear / renombrar / borrar + checkbox de filtro

Clic derecho en el icono de barra → NSMenu nativo
├── Abrir
├── About Clipboard Manager
└── Quit Clipboard Manager
```
