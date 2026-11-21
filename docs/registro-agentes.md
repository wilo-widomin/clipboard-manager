# Registro de agentes

Quién ha trabajado en qué, con qué modelo, y cuándo empezó y terminó. Lo lleva la
sesión principal: apunta cada agente al lanzarlo y lo cierra cuando termina.

Criterio de modelo, decidido por Willy el 2026-11-21: Haiku solo para lo muy sencillo
y bien explicado; Sonnet para lo claro y acotado; Opus para todo lo demás, y siempre
para lo que toca cifrado o puede perder datos; Fable si alguna tarea lo pide.

## Arreglos de seguridad del Mac (plan §3)

| Inicio | Fin | Agente | Modelo | Encargo | Resultado |
|---|---|---|---|---|---|
| 2026-11-21 11:41 | 2026-11-21 11:42 | `secreto-portapapeles` | Sonnet | §3.3: no guardar lo copiado con marca de secreto; marcar como secreto lo que se pega de un item protegido, que no salte al iPhone, y borrarlo a los 30 s. Archivos: `ClipboardMonitor.swift`, `PasteboardHelper.swift`, `StatusItemController.swift` y sus documentos de `agent-context`. Rama propia. | Hecho en su rama, revisado por la sesión principal; sin compilar. Efecto aparte: pegar un item protegido ya no lo sube arriba de la lista. |
| 2026-11-21 11:41 | 2026-11-21 11:51 | `cifrado-archivo` | Opus | §3.1: cifrar entero `store.json`, `groups.json` y las imágenes, con llave del aparato en el Keychain, y migrar lo que ya existe en claro sin perder nada. Archivos: `Persistence/`, `ClipboardItem.swift`, nuevos en `Security/`, donde se leen las imágenes, y sus documentos. Rama propia. | Hecho en su rama; sin compilar. Llave compartida con Widomin por nombre fijo. Si no puede leer los datos, avisa y se cierra sin escribir. |
| 2026-11-21 11:52 | — | (sesión principal) | Opus | Mezclar las dos ramas en `main` local. | Mezcladas sin conflictos; sin subir todavía. |
| 2026-11-21 11:53 | 2026-11-21 12:06 | `touchid-llave` | Opus | §3.2: el texto de los items protegidos, cifrado otra vez con una llave que el Mac solo entrega tras Touch ID o su contraseña; ventana de gracia de 15 min; migración de los protegidos que ya existen. Rama propia. | Hecho y mezclado a las 12:07; sin compilar. Proteger no pide el dedo, solo verlo. **Recorte:** con la firma de hoy, el que exige Touch ID es la app, no macOS; para que lo exija macOS hace falta firmar con perfil de Apple (decide Willy). |
| 2026-11-21 12:08 | 2026-11-21 12:14 | `arreglos-revision` | Opus | Arreglar lo que encontró `revision-seguridad-1` (letras A–H) encima de todo lo mezclado, y rehacer la lista de pruebas para el Mac. Rama propia. | Hecho y mezclado a las 12:15; sin compilar. El historial cifrado ahora se llama `store.enc`, así que una versión vieja ya no lo pisa; lo que esa versión vieja guarde se suma al volver a la nueva. |
| 2026-11-21 12:16 | 2026-11-21 12:21 | `revision-seguridad-2` | Opus | Revisión final de todo junto (§3.1, §3.2, §3.3 y arreglos), sobre todo errores de compilación. Solo lectura. | Nada grave. Tres puntos menores: una línea que quizá no compile, un caso raro en que se perdería texto protegido si la app y Widomin crean la llave a la vez, y dos guardados seguidos que podrían llegar desordenados. |
| 2026-11-21 12:21 | 2026-11-21 12:23 | `arreglos-revision-2` | Opus | Arreglar los tres puntos de `revision-seguridad-2`. Rama propia. | Hecho y mezclado; sin compilar. Si la app y Widomin crean la llave a la vez, ahora se detecta y no se cifra nada más hacia la llave huérfana (lo cifrado en ese instante no se recupera). |
| 2026-11-21 12:24 | 2026-11-21 12:24 | (sesión principal) | Opus | Subir todo a GitHub para que Willy compile en el Mac. | Subido. |
| 2026-11-21 11:53 | 2026-11-21 12:01 | `revision-seguridad-1` | Opus | Revisión de seguridad y de errores de compilación de §3.1 y §3.3 ya mezclados. Solo lectura. | Ningún error de compilación seguro. Un riesgo confirmado: una versión vieja de la app abierta después de la migración borraría el historial cifrado. Cuatro riesgos probables de pérdida de datos y uno de seguridad. Lo arregla `arreglos-revision` cuando termine `touchid-llave`, porque tocan los mismos archivos. |
| 2026-11-21 11:53 | 2026-11-21 11:54 | `docs-desfasados` | Haiku | Corregir tres frases que quedaron falsas: README (líneas 64 y 70), paso 5 de `historial/capturar-item.md` y el «Estado» del plan. Instrucciones exactas. Rama propia. | Hecho y mezclado. Detectó que su rama partía de una versión vieja (fallo mío, ver nota). Al cambiar el «Estado» se comió una fecha; la recuperé a mano. |

**Nota (11:54):** las ramas de los agentes nacen de la versión subida a GitHub, no de
la `main` local. `touchid-llave` arrancó sin §3.1 ni §3.3; le he avisado para que
mezcle `main` antes de seguir. A partir de ahora, cada encargo empieza con
`git merge main`.
