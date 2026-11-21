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
- **Lo que el plan deja abierto** (§12 de `05-blueprint-sync-android.md`): cómo se
  desbloquea un protegido en Linux, cómo se meten imágenes desde Android, en qué
  lenguaje va el servidor y el túnel para sincronizar fuera de casa.

## Hecho

- **Arreglos de seguridad del Mac** (21-11-2026): historial, grupos e imágenes cifrados;
  contraseñas protegidas con su propia llave; lo copiado desde un gestor de contraseñas
  no se guarda. Con la versión 1.10.2 Willy ve sus datos bien; faltan las pruebas
  de `prueba-seguridad-mac.md` (de la 3 a la 9).
