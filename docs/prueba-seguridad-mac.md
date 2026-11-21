# Prueba a mano de los arreglos de seguridad del Mac

Para Willy, con la versión 1.10.2 o posterior instalada desde el `.dmg` de
`./scripts/build-release.sh`. Los pasos 1 y 2 (copia de seguridad e instalación) ya
están hechos.

**Nunca** borres en Acceso a Llaveros las llaves «clipboard-manager»: sin ellas el
historial no se puede abrir.

## 3. Que el historial ya no se lee sin cifrar

```
cd ~/Library/Application\ Support/ClipboardManager && ls -la && head -c 4 store.enc; echo; grep -c textContent store.enc
```

Tiene que salir `store.enc` (sin ningún `store.json`), después `CLPE` y después `0`.

## 4. Contraseña copiada desde un gestor

Copia una contraseña desde Contraseñas de Apple (o 1Password, KeeWeb…). No debe
aparecer en la lista.

## 5. Pegar un item protegido

Pégalo en otra app: pide el dedo una vez y se pega bien. Espera 30 segundos sin copiar
nada y prueba a pegar otra vez: ya no debe pegar nada.

## 6. Contraseña nueva protegida

Con «Nueva contraseña», crea una protegida: al guardar no pide el dedo. Pégala: pide
el dedo; si la vuelves a pegar antes de 15 minutos, ya no lo pide.

## 7. Desproteger y volver a proteger

En el editor (clic derecho en la fila), quita «Protegido» y guarda: se ve el texto en
la lista. Vuelve a protegerlo: para verlo vuelve a pedir el dedo.

## 8. Cerrar y abrir

Cierra la app y ábrela: todo sigue ahí. Si macOS pide permiso para usar la llave,
pulsa «Permitir siempre».

## 9. Borrar la copia de seguridad

Solo si todo lo anterior ha ido bien, porque la copia está sin cifrar:

```
rm -rf ~/Desktop/ClipboardManager-copia
```
