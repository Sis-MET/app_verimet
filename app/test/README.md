# Tests de la app

`online/` cubre el flujo con sesion —login, catalogo, captura, borradores,
historial, consentimiento y PDF— con un transporte sintetico (`fakes.dart`,
`customer_fakes.dart`) en vez de pegarle a Supabase. Ahi estan tambien los
widget tests, que localizan cada campo con `fieldLabeled` de `finders.dart`.

`features/<prueba>/domain/` cubre la matematica de tolerancias de las tres
pruebas metrologicas. La app no evalua en el cliente —Supabase recalcula al
finalizar—, asi que estos tests valen como especificacion ejecutable de lo que
el servidor debe replicar.

Correr con `flutter test`.
