# Tests de la app

Correr con `flutter test` (o `pnpm app:test` desde la raiz).

`test/flutter_test_config.dart` carga las fuentes reales —Barlow, Barlow
Condensed y la familia de iconos de Material— antes de cualquier test. Sin eso
el motor de pruebas dibuja una fuente de bloques: los goldens no valdrian nada
y las medidas de texto no se pareceran a las del dispositivo.

## `online/` — comportamiento

Cubre el flujo con sesion (login, catalogo, captura, borradores, historial,
consentimiento y PDF) con un transporte sintetico (`fakes.dart`,
`customer_fakes.dart`) en vez de pegarle a Supabase. Los campos se localizan
con `fieldLabeled` de `finders.dart`, porque el rotulo va fuera de la caja y no
es descendiente del control.

## `features/<prueba>/domain/` — metrologia

La matematica de tolerancias de las tres pruebas. La app no evalua en el
cliente —Supabase recalcula al finalizar—, asi que estos tests valen como
especificacion ejecutable de lo que el servidor debe replicar.

## `shared/golden/` — sistema visual

Fotografias de cada pieza del sistema en tema claro y oscuro. Existen porque el
sistema se rompio dos veces por cambios puramente esteticos que ningun test
veia: un modulo que desbordaba y unos apartados plegables que quedaban pegados.
Un desbordamiento hace fallar el test aunque nadie mire la imagen, porque
`RenderFlex overflowed` levanta una excepcion.

Cuando el cambio de diseno sea intencionado:

```
flutter test --update-goldens        # o: pnpm app:goldens
```

y **revisar el diff de los .png antes de comitearlos** — regenerar sin mirar
convierte el golden en un sello de goma.

Las imagenes son exactas al pixel y dependen del motor de render, asi que se
generaron en Windows. Si algun dia hay CI en Linux habra que regenerarlas alli
o marcar estos tests con un `tag` y no correrlos fuera de su plataforma.
