# Prueba a mano: modelo preparado para sincronizar (plan §6)

Para Willy. Este cambio no añade nada visible: la app tiene que funcionar **igual que
antes**. Lo que se prueba es que no se ha roto nada.

Antes de empezar, asegúrate de que no queda ninguna versión vieja de la app en el Mac
(si se abre una vieja después, verá los datos raros):

```
mdfind "kMDItemCFBundleIdentifier == 'com.clipboardmanager.app'"
```

## 1. Compilar y pasar los tests

Desde la carpeta del proyecto en el Mac:

```
git pull && swift test && ./scripts/build-release.sh
```

`swift test` tiene que terminar sin fallos. Si dice que no encuentra XCTest:

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Instala el `.dmg` de `dist/` sustituyendo la app de Aplicaciones.

## 2. Que todo sigue igual

1. Al abrir, están el historial, los favoritos, los grupos y las contraseñas protegidas.
2. Copiar algo que ya está no lo duplica y conserva estrella, grupo y nota.
3. Borrar un favorito con la papelera: desaparece y no vuelve al cerrar y abrir.
4. Borrar un grupo: sus items se quedan sin grupo y el grupo no vuelve al cerrar y abrir.
5. Los chips de grupo, «Sin grupo» y el buscador filtran como antes.
6. Editar texto, nota, título y protección, y crear una contraseña a mano, se guarda bien.
7. Cerrar y abrir: todo sigue ahí.
