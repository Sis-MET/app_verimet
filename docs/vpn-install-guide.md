# Guia de instalacion de la VPN corporativa

> Dirigida al personal de sistemas del cliente y al operador que va a usar
> IvMET en planta.

## 1. Por que hace falta

La API de IvMET y el SQL Server viven en la red interna de **Metrica Ltda**.
No estan publicados en internet. Para que el celular pueda enviar las
verificaciones, primero tiene que estar dentro de esa red a traves de la VPN.

**La app no gestiona el tunel.** IvMET solo hace llamadas HTTPS normales: es el
cliente VPN del sistema operativo el que levanta la conexion. Por eso la VPN se
instala y se conecta *antes* de abrir la app.

> **Sin VPN la app igual funciona.** Se pueden ejecutar y guardar las
> verificaciones; quedan en el celular en estado *pendiente de sincronizar* y se
> envian solas cuando haya VPN. Ver la seccion `sync` en
> [architecture.md](./architecture.md).

## 2. Datos que entrega Metrica

Antes de empezar, el area de sistemas de Metrica entrega por un canal seguro:

| Dato | Ejemplo | Notas |
| --- | --- | --- |
| Archivo de configuracion | `ivmet-<usuario>.conf` (WireGuard) u `ovpn` (OpenVPN) | Es **personal e intransferible**. |
| Host de la API | `api.metrica.local` | Solo resuelve con la VPN conectada. |
| Contacto de soporte | telefono / correo de mesa de ayuda | Para bloqueos y renovaciones. |

TODO(Metrica): completar con los valores reales de produccion antes de
publicar esta guia a los clientes.

## 3. WireGuard (recomendado)

### Android

1. Instalar **WireGuard** desde Google Play.
2. Transferir el archivo `.conf` al telefono por un medio seguro (no WhatsApp
   ni correo personal).
3. Abrir WireGuard y tocar **+** -> **Importar desde archivo o archivo ZIP**.
4. Seleccionar el `.conf` recibido.
5. Activar el interruptor del tunel. Deberia aparecer el icono de llave en la
   barra de estado.
6. Verificar: abrir el navegador e ir a `https://api.metrica.local/health`.
   Debe responder un JSON con `"status": "ok"`.

### iOS

Mismo flujo con la app **WireGuard** de la App Store. En iOS conviene importar
escaneando el codigo QR que genera Metrica en vez de mover el archivo.

### Windows (para el equipo de desarrollo)

1. Descargar el cliente oficial desde <https://www.wireguard.com/install/>.
2. **Agregar tunel** -> seleccionar el `.conf`.
3. **Activar**.
4. Comprobar desde una terminal:

```bash
curl https://api.metrica.local/health
```

## 4. OpenVPN (alternativa)

1. Instalar **OpenVPN Connect** (Play Store / App Store / escritorio).
2. Importar el perfil `.ovpn`.
3. Ingresar usuario y contraseña provistos por Metrica cuando lo pida.
4. Conectar y verificar el endpoint `/health` igual que arriba.

## 5. Problemas frecuentes

| Sintoma | Causa probable | Que hacer |
| --- | --- | --- |
| La app dice "Sin conexion con el servidor. Verifique la VPN." | El tunel esta apagado o se cayo. | Reactivar el tunel y reintentar la sincronizacion. |
| El tunel esta activo pero no resuelve `api.metrica.local` | Falta el DNS interno en el perfil. | Pedir a Metrica un perfil con el `DNS` correcto. |
| Conecta con datos moviles pero no con el WiFi de la planta | La red de planta bloquea UDP/51820. | Pedir a sistemas del cliente que habilite el puerto, o usar el perfil TCP de OpenVPN. |
| "Certificado del servidor no es valido" | El dispositivo no confia en la CA interna de Metrica. | Instalar el certificado raiz que entrega Metrica. |
| Andaba y dejo de andar | Perfil vencido o revocado. | Contactar a soporte de Metrica para renovarlo. |

## 6. Seguridad

- El perfil de VPN identifica a **una persona**: no se comparte entre operadores.
- Si se pierde o roba el telefono, avisar de inmediato a Metrica para revocar el
  perfil y cerrar la sesion de IvMET.
- Nunca guardar el `.conf` en carpetas sincronizadas a nubes personales.
