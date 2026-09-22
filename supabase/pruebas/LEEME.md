# Probar la seguridad del esquema de verdad

Leer un `create policy` y convencerse de que está bien no es probarlo.
Esto levanta un Postgres de usar y tirar en tu Mac, le aplica
`schema.sql` tal cual, y **ataca**: se hace pasar por otro usuario e
intenta leer, borrar y modificar datos ajenos; intenta auto-invitarse;
intenta llenar la base; intenta colarse en el registro.

Son 30 intentos. Cada uno imprime `PASA` (el ataque no funcionó, que es
lo que se busca) o `FALLA`.

## ⚠️ Esto NO se ejecuta en tu Supabase

`02-ataque.sql` crea usuarios, llena tablas hasta el tope y cambia el
modo de registro. Va en una base de datos de mentira, en tu ordenador.
Para comprobar tu proyecto de verdad está `../comprobar-seguridad.sql`,
que solo mira y no toca nada.

## Cómo se ejecuta

Hace falta Postgres en local. En un Mac:

```bash
brew install postgresql@16
brew services start postgresql@16
```

Y desde la raíz del repo:

```bash
dropdb --if-exists habitium_prueba
createdb habitium_prueba

psql -d habitium_prueba -q -f supabase/pruebas/01-entorno-falso.sql
psql -d habitium_prueba -q -f supabase/schema.sql
psql -d habitium_prueba -f supabase/pruebas/02-ataque.sql 2>&1 \
  | grep -E "PASA|FALLA|═══"
```

Lo que tiene que salir: 30 `PASA` y ningún `FALLA`.

Al terminar, `dropdb habitium_prueba` y no queda rastro.

## Qué comprueba cada bloque

| Bloque | Pregunta |
|---|---|
| 1 | ¿Puede una cuenta ver, borrar o modificar los datos de otra? |
| 2 | ¿Puede alguien cambiar el dueño de una fila para robarla o colarla? |
| 3 | ¿Puede hacer algo un visitante sin cuenta? |
| 4 | ¿Son invisibles de verdad la lista de invitados y el control de registro? |
| 5 | ¿Se puede llenar la base con campos enormes o millones de filas? |
| 6 | ¿Funciona el portero del registro en sus tres modos? |

## Un aviso sobre las pruebas mismas

La primera versión de `02-ataque.sql` daba **aprobados falsos**, y vale
la pena saber por qué porque es la trampa clásica al probar seguridad:

- El portero del registro impedía crear a las dos víctimas, así que los
  bloques 1 y 2 corrían sobre tablas **vacías**. Todo pasaba, y no
  demostraba nada. Por eso ahora hay una prueba de control ("Ana sí ve lo
  suyo") cuyo trabajo es fallar si las demás no valen.
- La prueba de inundación envolvía el bucle entero en un
  `begin/exception`, y al saltar la excepción Postgres deshacía también
  las 100 inserciones buenas: el recuento salía 0 y parecía un fallo del
  esquema que no existía. El manejador va **dentro** del bucle.

Una prueba de seguridad que siempre pasa no es una buena prueba: es una
que no está mirando.
