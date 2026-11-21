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

## Fallo en la primera prueba de Willy

| Inicio | Fin | Agente | Modelo | Encargo | Resultado |
|---|---|---|---|---|---|
| 2026-11-21 13:22 | 2026-11-21 13:26 | `diagnostico-protegidos` | Opus | Willy ve los items protegidos sin proteger y sin título tras instalar la versión nueva. Encontrar la causa, decir si los datos se pueden recuperar y cómo. Solo lectura. | El código nuevo no pierde esos campos. Causa probable: una versión vieja de la app (anterior a los protegidos) reescribió `store.json` antes de migrar, como sospechaba Willy. Se recupera desde la copia del escritorio, que conserva los 28. |
| 2026-11-21 11:53 | 2026-11-21 12:01 | `revision-seguridad-1` | Opus | Revisión de seguridad y de errores de compilación de §3.1 y §3.3 ya mezclados. Solo lectura. | Ningún error de compilación seguro. Un riesgo confirmado: una versión vieja de la app abierta después de la migración borraría el historial cifrado. Cuatro riesgos probables de pérdida de datos y uno de seguridad. Lo arregla `arreglos-revision` cuando termine `touchid-llave`, porque tocan los mismos archivos. |
| 2026-11-21 11:53 | 2026-11-21 11:54 | `docs-desfasados` | Haiku | Corregir tres frases que quedaron falsas: README (líneas 64 y 70), paso 5 de `historial/capturar-item.md` y el «Estado» del plan. Instrucciones exactas. Rama propia. | Hecho y mezclado. Detectó que su rama partía de una versión vieja (fallo mío, ver nota). Al cambiar el «Estado» se comió una fecha; la recuperé a mano. |

**Nota (11:54):** las ramas de los agentes nacen de la versión subida a GitHub, no de
la `main` local. `touchid-llave` arrancó sin §3.1 ni §3.3; le he avisado para que
mezcle `main` antes de seguir. A partir de ahora, cada encargo empieza con
`git merge main`.

**Resuelto (2026-11-21):** Willy estaba viendo la lista de una versión vieja de la app
que seguía abierta. Con la 1.10.2 se ve todo bien: no se había perdido nada.

## Fallos de la prueba a mano (2026-11-21)

| Inicio | Fin | Agente | Modelo | Encargo | Resultado |
|---|---|---|---|---|---|
| 2026-11-21 13:45 | 2026-11-21 13:45 | `gestores-contrasenas` | Sonnet | Lo copiado desde el llavero de Apple sigue entrando en la lista: no capturar nada cuando la app de delante es un gestor de contraseñas (Acceso a Llaveros, Contraseñas, 1Password…). Solo `ClipboardMonitor.swift`. Rama propia. | Hecho y mezclado; sin compilar. Lista de 18 gestores; algunos identificadores sin confirmar (si no existen, no hacen nada). |
| 2026-11-21 13:45 | 2026-11-21 13:45 | `ventana-editor` | Sonnet | La ventana del editor no vuelve al frente al hacer clic derecho otra vez, y abrir un item ya abierto crea otra pestaña. Reutilizar la ventana de ese item y traerla delante. Rama propia. | Hecho y mezclado; sin compilar. No había un arreglo anterior perdido. Las ventanas ya no se agrupan en pestañas. |

## Siguiente fase: Android local y modelo sincronizable (plan §4 y §6)

| Inicio | Fin | Agente | Modelo | Encargo | Resultado |
|---|---|---|---|---|---|
| 2026-11-21 13:52 | 2026-11-21 14:07 | `android-base-cifrada` | Opus | Repo de Android, rama `feat/app-local-cifrada`: que compile el trabajo de agosto; modelo con grupos y protegidos; base entera cifrada (SQLCipher + Keystore); protegidos con llave que exige huella o patrón al sistema; crear, copiar, favoritos, grupos, buscador; tests; quitar la dirección de casa del documento. Puede compilar aquí. | Hecho en su rama: compila y pasan 33 tests (lo repetí yo a las 14:07). La huella la exige Android, no la app. Falta probarlo en el móvil. Imágenes y pulido de tablet, para la siguiente tarea. |
| 2026-11-21 14:08 | 2026-11-21 14:10 | `revision-android` | Opus | Revisión de seguridad y de pérdida de datos de la rama de Android. Solo lectura. | Cifrado bien. Dos riesgos de perder datos (borrar la base cifrada si falta la llave; llave invalidada usada para guardar), las contraseñas se guardaban recortadas, el teclado podía aprenderlas y dos fugas menores en memoria. |
| 2026-11-21 14:10 | — | `arreglos-android` | Opus | Arreglar los seis puntos de `revision-android` en la misma rama, con tests. | en curso |
| 2026-11-21 13:52 | 2026-11-21 14:06 | `modelo-sincronizable` | Opus | Mac (§6): identificador de aparato, fecha y aparato por cada campo, borrados marcados para lo que se sincroniza, huella de las imágenes, la regla de fusión y sus casos de prueba compartidos. Sin red. Rama propia. | Hecho en su rama; sin compilar. Los casos de prueba los comprobó con una versión aparte en Python. Pendiente de revisión. |
| 2026-11-21 14:06 | 2026-11-21 14:11 | `revision-modelo` | Opus | Revisar la rama del modelo sincronizable antes de mezclarla: compilación, datos reales y regla de fusión. Solo lectura. | Sin errores de compilación a la vista; casos de prueba correctos. Dos problemas: las marcas de borrado en el mismo archivo romperían una versión vieja o Widomin; y texto y protección se mezclaban por separado. |
| 2026-11-21 14:11 | 2026-11-21 14:16 | `arreglos-modelo` | Opus | Arreglar los dos problemas de `revision-modelo` en la misma rama. | Hecho y mezclado en `main`; sin compilar. Borrados en archivos aparte; texto y protección viajan juntos. 18 casos de prueba comprobados con la versión en Python. |
