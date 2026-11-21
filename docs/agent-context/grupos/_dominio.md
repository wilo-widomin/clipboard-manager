---
dominio: grupos
actualizado: 2026-11-21
archivos:
  - Sources/ClipboardManagerKit/Models/ClipboardGroup.swift
  - Sources/ClipboardManagerKit/Models/ClipboardStore.swift
  - Sources/ClipboardManagerKit/UI/PopoverRootView.swift
depende_de: [historial/_dominio]
---

# Grupos

Etiquetas que el usuario crea para organizar sus favoritos y filtrar las listas.
Un item pertenece **como mucho a un grupo**.

## Entidades

- `ClipboardGroup` (`Models/ClipboardGroup.swift`) — `id`, `name`, `isFilterEnabled`
  (selección del filtro, no una propiedad del grupo en sí), `nameStamp?` y
  `deletion?` (modelo sincronizable, ambos con `decodeIfPresent`). Tiene `init(from:)`
  propio: `isFilterEnabled` ausente decodifica como `false`, para que al actualizar
  no aparezca de golpe un filtro que esconda medio historial.
- Persistencia aparte en `groups.enc` (`persistGroups()`), no dentro de `store.enc`.

## Invariantes

- Asignar grupo **auto-favorita** el item, para que sobreviva al cap por tipo;
  des-favoritar lo saca del grupo.
- Borrar un grupo conserva sus items y solo les limpia `groupID`.
- Nombres duplicados permitidos (la identidad es el `id`); nombre vacío o solo
  espacios se rechaza al crear y al renombrar.
- `assignGroup` ignora ids de grupo desconocidos.
- La **selección** del filtro no se persiste entre arranques (`load()` la limpia),
  aunque `groups.enc` la escriba.
- **Borrar un grupo deja tombstone** (`ClipboardGroup.tombstone`, sin nombre) en
  `store.groupTombstones`, que se guarda en `groups.enc` con los vivos pero nunca
  está en `store.groups`: chips, casillas, menú 📁 y `assignGroup` no lo ven. Los
  items que tenía pierden `groupID` con su marca `group`.
- **Renombrar marca `nameStamp`** (solo si el nombre cambia). Un grupo sin marca
  tiene la implícita `SyncStamp.legacyGroup` (1-1-1970): los grupos no tienen fecha
  de creación. `isFilterEnabled` no lleva marca ni se sincroniza (§2 del blueprint).
  Detalle del modelo y de la fusión en `historial/_dominio.md`, «Modelo sincronizable».

## Acciones documentadas

- [Asignar y gestionar grupos](asignar-grupo.md)
- [Filtrar por grupo](filtrar-por-grupo.md)

## Trampas

- Como solo los favoritos tienen grupo, "sin grupo" incluye **todos** los no
  favoritos: por eso el chip "Sin grupo" es el que hace visible el grueso del
  historial.
- Un item cuyo grupo fue borrado cuenta como no agrupado en `passesGroupFilter`
  (`groupID` ya viene limpio, pero la comprobación tolera además ids huérfanos).
