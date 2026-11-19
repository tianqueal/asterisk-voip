# Despliegue con Docker (alternativa a la máquina virtual)

Además de `vm/despliegue_asterisk.sh` (VirtualBox, ver [vm.md](vm.md)), la centralita puede ejecutarse
en un contenedor. Usa **los mismos ficheros de `configs/`**, así que el
comportamiento es el mismo: extensiones 1001/1002, buzón de voz (600, 6001,
6002), prueba de eco (500) y locuciones en español.

|                          | Máquina virtual                            | Docker                                      |
| ------------------------ | ------------------------------------------ | ------------------------------------------- |
| Arranque                 | minutos (descarga de imagen e instalación) | segundos                                    |
| Tamaño                   | imagen de disco completa                   | ~50 MB (~22 MB comprimida)                  |
| Asterisk                 | 20 (Debian 12) / 16 (Debian 11)            | 20.11 (Alpine 3.22)                         |
| Actualizar configuración | `vm/actualizar_config.sh`                  | `docker compose exec asterisk cda-recargar` |

## Requisitos

- Docker Engine 23+ o Docker Desktop (Windows / macOS), con Compose v2.
- Los móviles (Linphone, Zoiper…) en la misma red que el equipo que ejecuta Docker.

## Puesta en marcha rápida

1. Averigua la IP de tu equipo en la red de los móviles (wifi/LAN):
   - Windows: `ipconfig` → "Dirección IPv4" del adaptador wifi/Ethernet
   - Linux: `ip -4 addr` · macOS: `ipconfig getifaddr en0`

2. Crea un fichero `.env` en la raíz del repositorio con esa IP:

   ```dotenv
   EXTERNAL_IP=192.168.1.50
   ```

3. Construye y arranca:

   ```bash
   docker compose up -d --build
   ```

4. Comprueba que está sano (`healthy`) y mira el log:

   ```bash
   docker compose ps
   docker compose logs -f asterisk
   ```

5. Configura los móviles:

   | Campo              | Valor                                                    |
   | ------------------ | -------------------------------------------------------- |
   | Servidor / dominio | la `EXTERNAL_IP` del paso 1 (puerto 5060, **UDP** o TCP) |
   | Usuario            | `1001` o `1002`                                          |
   | Contraseña         | `1234` / `1234` (ver `configs/pjsip.conf`)               |

   Llama al **500** (eco) para comprobar el audio en los dos sentidos.

## ¿Por qué hace falta `EXTERNAL_IP`?

Con la red por defecto de Docker (bridge), Asterisk solo ve la IP interna del
contenedor (172.x.x.x) y la anunciaría a los móviles en el SDP. Estos
enviarían el audio a una dirección inalcanzable: la llamada conecta pero **no
se oye nada**. Con `EXTERNAL_IP`, al arrancar se añade a los transportes
`transport-udp` y `transport-tcp` lo siguiente (solo dentro del contenedor,
`configs/pjsip.conf` no se toca):

```ini
[transport-udp](+)   ; y lo mismo para [transport-tcp](+)
external_media_address=<EXTERNAL_IP>
external_signaling_address=<EXTERNAL_IP>
```

No se declara la red interna del contenedor como `local_net`: en Docker
Desktop (Windows/macOS) todos los móviles llegan con la IP de la puerta de
enlace de Docker (`172.x.0.1`), y si esa red se considerase "local", Asterisk
anunciaría su IP interna en vez de `EXTERNAL_IP` (la llamada se contesta pero
no hay audio y termina con un 408 por falta de ACK).

Si hay clientes en una red que no debe reescribirse, añádela con `LOCAL_NET`
(separando varias por espacios, se añaden como `local_net=`).

## Uso diario

```bash
# Consola de Asterisk (equivalente a "asterisk -rvvv" en la VM)
docker compose exec asterisk asterisk -rvvv

# Comandos sueltos
docker compose exec asterisk asterisk -rx "pjsip show contacts"
docker compose exec asterisk asterisk -rx "voicemail show users"

# Tras editar algo en configs/ (PJSIP, dialplan, voicemail): recarga en caliente
docker compose exec asterisk cda-recargar

# Tras cambiar modules.conf o los bloques [transport-*]: reinicio
docker compose restart

# Parar (los mensajes de voz se conservan en el volumen "buzones")
docker compose down

# Parar y borrar también los mensajes de voz
docker compose down -v
```

`configs/` se monta en el contenedor como solo lectura, así que **no hace
falta reconstruir la imagen** para cambiar la configuración. La imagen lleva
además una copia de `configs/` del momento del build, por si se ejecuta sin el
montaje (por ejemplo en otro equipo).

## Variables de entorno

| Variable          | Por defecto                   | Descripción                                                                     |
| ----------------- | ----------------------------- | ------------------------------------------------------------------------------- |
| `EXTERNAL_IP`     | _(vacía)_                     | IP del host que se anuncia a los móviles. Necesaria con red bridge.             |
| `LOCAL_NET`       | _(vacía)_                     | Redes adicionales consideradas internas (`192.168.0.0/16 10.0.0.0/8`).          |
| `RTP_PORT_START`  | `10000`                       | Primer puerto UDP de audio/vídeo.                                               |
| `RTP_PORT_END`    | `10099`                       | Último puerto UDP de audio/vídeo (~50 llamadas simultáneas).                    |
| `PJSIP_TRANSPORT` | `transport-udp transport-tcp` | Transportes (separados por espacios) a los que se añaden los parámetros de NAT. |

`compose.yaml` publica automáticamente el rango RTP indicado. El rango es
corto a propósito: Docker publica cada puerto por separado y abrir los
10 000 puertos que usa Asterisk por defecto hace el arranque muy lento.

## Sin Compose (`docker run`)

```bash
docker build -f docker/Dockerfile -t asterisk-cda .

docker run -d --name asterisk-cda --init --restart unless-stopped \
  -e EXTERNAL_IP=192.168.1.50 \
  -p 5060:5060/udp -p 10000-10099:10000-10099/udp \
  -v "$PWD/configs:/config:ro" -v buzones:/var/spool/asterisk \
  --cap-drop ALL --security-opt no-new-privileges \
  asterisk-cda
```

Puedes añadir argumentos tras el nombre de la imagen y se pasarán a
`asterisk -f` (por ejemplo, `asterisk-cda -vvvvv`). Sin argumentos se usa `-vvv`.

En PowerShell, cambia `"$PWD/configs"` por `"${PWD}/configs"` y las `\` de
final de línea por `` ` ``.

### Red del host (solo Linux, la opción más fiable)

En Linux el contenedor puede usar directamente la red del equipo. No hay NAT,
así que no hacen falta `EXTERNAL_IP` ni publicar puertos:

```bash
docker run -d --name asterisk-cda --init --network host \
  -v "$PWD/configs:/config:ro" -v buzones:/var/spool/asterisk asterisk-cda
```

(En Docker Desktop para Windows/macOS `--network host` no expone los puertos a
la red local: usa la red bridge con `EXTERNAL_IP`).

## IP propia para la centralita

Con la configuración por defecto, la centralita usa la IP de tu equipo
(`EXTERNAL_IP`). Si prefieres que tenga una dirección propia en la red local,
como ocurre con la máquina virtual, las opciones dependen del sistema operativo.

### Por qué la VM sí tiene IP propia y Docker Desktop no

VirtualBox, en modo puente (_bridged_), instala un driver que se engancha a la
tarjeta de red física. La VM tiene su propia tarjeta virtual y sus tramas salen
directamente a la LAN, así que el router la ve como un dispositivo más y le
asigna una IP por DHCP. Por wifi, VirtualBox además traduce la MAC para que el
punto de acceso no descarte esas tramas.

```
Router ── [tarjeta física]
              ├── Windows       192.168.1.50
              └── VM (puente)   192.168.1.60
```

Docker Desktop (Windows/macOS) ejecuta los contenedores dentro de una VM Linux
propia (WSL2/Hyper-V) que está detrás de un NAT interno, no en modo puente. Una
red `macvlan` creada ahí se engancha a la tarjeta virtual de esa VM, así que la
IP que reciba el contenedor solo existe dentro de esa red interna y la LAN no
puede verla.

```
Router ── [tarjeta física] ── Windows 192.168.1.50
                                 └─ NAT ── VM de Docker 172.x
                                              └── contenedor → invisible para la LAN
```

En Linux no hay VM intermedia: Docker usa el kernel del equipo y puede
conectar el contenedor directamente a la tarjeta real, igual que VirtualBox.

### Linux: red `ipvlan` o `macvlan`

Así el contenedor tiene su propia IP en la LAN. No hay NAT, así que no hacen
falta ni `EXTERNAL_IP` ni publicar puertos:

```yaml
services:
  asterisk:
    networks:
      lan:
        ipv4_address: 192.168.1.60 # IP libre, fuera del rango DHCP del router

networks:
  lan:
    driver: ipvlan # o macvlan
    driver_opts:
      parent: eth0 # interfaz del equipo conectada a la LAN
      ipvlan_mode: l2
    ipam:
      config:
        - subnet: 192.168.1.0/24
          gateway: 192.168.1.1
```

- Por wifi, usa `ipvlan`. `macvlan` da al contenedor una MAC distinta, y muchos
  puntos de acceso descartan las tramas con MAC desconocidas.
- El propio equipo no puede comunicarse con esa IP sin crear una interfaz
  puente adicional. Los móviles y el resto de la red sí pueden.
- Reserva la IP en el router para que no se la asigne a otro dispositivo.

### Windows/macOS

- **Docker dentro de la VM de VirtualBox en modo puente**: la VM ya tiene IP
  propia, y el contenedor usa `--network host` como en
  [Red del host](#red-del-host-solo-linux-la-opción-más-fiable).
- **Segunda IP en el equipo**: puedes añadir otra IP estática a tu tarjeta de
  red y publicar los puertos solo en ella, con `EXTERNAL_IP` apuntando a esa IP.
  Sigue habiendo NAT, pero la centralita queda en su propia dirección. Windows
  no admite IPs adicionales con DHCP, así que la tarjeta debe pasar a
  configuración estática.

  ```yaml
  ports:
    - "192.168.1.60:5060:5060/udp"
    - "192.168.1.60:10000-10099:10000-10099/udp"
  ```

- **Docker Desktop con `EXTERNAL_IP`** (opción por defecto): la centralita
  comparte la IP del equipo, y `cda-config` se encarga del NAT.

## Cómo está construida la imagen

- **Alpine 3.22 + paquete `asterisk` oficial de Alpine**: nada se compila, el
  build tarda segundos y la imagen final ocupa unos 50 MB.
- **Build multietapa**: las locuciones en español (`asterisk-core-sounds-es-gsm`
  1.6.1, con suma SHA-256 verificada), la zona horaria `Europe/Madrid` y
  `indications.conf` se preparan en una etapa intermedia. A la imagen final
  solo llegan esos ficheros, no `tzdata` completo ni los ejemplos de
  configuración.
- **Configuración generada al arrancar** (`docker/cda-config`), por capas:
  `docker/asterisk/` (ajustes propios del contenedor) → `configs/` copiada en
  la imagen → `configs/` montada en `/config`. La última capa prevalece.
  `/etc/asterisk` se vacía en cada arranque, ya que el sistema de ficheros del
  contenedor se conserva entre reinicios. Los ficheros del host no se modifican.
- **Módulos**: el paquete solo trae lo necesario, y `modules.conf` usa
  `autoload=yes`. A diferencia de la VM, el contenedor solo incluye los `.conf`
  necesarios, y con `autoload=yes` un módulo sin su fichero llena el log de
  errores. Por ello, los módulos opcionales cuyo `.conf` no existe (colas,
  conferencias, ARI…) se desactivan para que el log quede limpio. Si añades por
  ejemplo `queues.conf` a `configs/`, `app_queue` vuelve a cargarse tras un
  `docker compose restart`.
- **Seguridad**: Asterisk se ejecuta como el usuario `asterisk` (no root), sin
  capacidades de Linux (`cap_drop: ALL`) y con `no-new-privileges`.
- **Log**: todo sale por la salida estándar (`docker compose logs`). El
  contenedor no escribe logs en disco.
- **Healthcheck**: `asterisk -rx "core show uptime"` cada 30 s.

### Estructura

```
compose.yaml                     # en la raíz: "docker compose up" sin parámetros
docker/
├── Dockerfile
├── Dockerfile.dockerignore      # solo se envía configs/ y docker/ al build
├── entrypoint.sh        # cda-config + exec asterisk -f
├── cda-config           # genera /etc/asterisk (capas, NAT, RTP, módulos)
├── cda-recargar         # cda-config + reload de PJSIP, dialplan y voicemail
└── asterisk/
    ├── asterisk.conf    # rutas e idioma por defecto (es)
    └── logger.conf      # log a la consola del contenedor
```

## Solución de problemas

| Síntoma                                             | Causa probable                                                                                                              |
| --------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| El móvil no se registra                             | IP del servidor errónea, o el cortafuegos del host bloquea 5060/UDP (en Windows, permite Docker Desktop en redes privadas). |
| La llamada conecta pero no hay audio                | Falta `EXTERNAL_IP` o no es la IP del host en la wifi; o el rango RTP no está publicado.                                    |
| Audio en un solo sentido                            | `EXTERNAL_IP` apunta a otra interfaz (VPN, adaptador virtual de VirtualBox/WSL…).                                           |
| Los cambios de `configs/` no se aplican             | Ejecuta `cda-recargar`; para `modules.conf` o el transporte, `docker compose restart`.                                      |
| Ver qué configuración se ha generado                | `docker compose exec asterisk cat /etc/asterisk/pjsip.conf`                                                                 |
| En el log: `no local system nameservers configured` | Aviso inofensivo por el DNS de Docker; no afecta a las llamadas.                                                            |
