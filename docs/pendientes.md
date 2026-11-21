# Pendientes

Lo que queda por hacer o por decidir, escrito para Willy. Cuando algo se resuelve,
pasa a «Hecho» en el mismo cambio.

## Por hacer

- **Que sea macOS, y no la app, quien exija Touch ID para las contraseñas protegidas.**
  Hoy el dedo lo pide la app; para que lo pida el propio Mac hay que firmar la app con
  un permiso especial de Apple. Falta averiguar si basta el certificado de desarrollador
  que ya hay en el Mac o si hace falta la cuenta de pago (unos 99 € al año). Aplazado
  por Willy el 21-11-2026. Detalle en `05-blueprint-sync-android.md`, §3.2.
- **Quitar la dirección de la red de casa** que aparece en un documento del proyecto de
  Android (`docs/agent-context/arquitectura.md` de `clipboard-manager-android`). No debe
  estar en el repositorio.
- **Copias antiguas de Time Machine.** Las copias hechas antes del 21-11-2026 guardan el
  historial sin cifrar. Para quitarlo de ahí hay que borrar esas copias.
- **Que los borrados guardados no crezcan sin fin.** Desde el modelo sincronizable, borrar
  un favorito o un grupo deja una marca de «borrado» (sin el contenido) para que no
  resucite desde otro aparato. Hoy no se limpian nunca: ocupan muy poco, pero cuando haya
  sincronización hay que borrarlas cuando todos los aparatos las tengan (propuesta: y, como
  mucho, a los 90 días). Detalle en `docs/agent-context/historial/_dominio.md`.
- **Dos avisos del compilador** (no son errores; salieron en `swift test` el 21-11-2026):
  `PasteTargetTracker.swift:104` y `ProtectedAccess.swift:137`, de concurrencia. Limpiarlos
  cuando se toque esa zona.
- **Lo que el plan deja abierto** (§12 de `05-blueprint-sync-android.md`): cómo se
  desbloquea un protegido en Linux, cómo se meten imágenes desde Android, en qué
  lenguaje va el servidor y el túnel para sincronizar fuera de casa.

## Hecho

- **Arreglos de seguridad del Mac** (21-11-2026): historial, grupos e imágenes cifrados;
  contraseñas protegidas con su propia llave; lo copiado desde un gestor de contraseñas
  no se guarda, tampoco desde el llavero de Apple. Willy pasó todas las pruebas de
  `prueba-seguridad-mac.md` el 21-11-2026.
- **Ventana del editor** (21-11-2026): un item ya abierto no abre otra ventana; la que
  hay vuelve al frente aunque esté tapada o minimizada. Probado por Willy.
