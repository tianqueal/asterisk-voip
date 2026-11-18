# Centralita VoIP con Asterisk — Trabajo grupal CDA

Centros de Datos, 2026/27. Centralita Asterisk (PJSIP) para dos móviles con
Linphone o Zoiper.

| Extensión | Función |
|---|---|
| `1001`, `1002` | Llamada entre los móviles (si no contesta, buzón de voz) |
| `600` | Consultar el buzón propio (PIN `1234`) |
| `6001`, `6002` | Dejar un mensaje directamente en el buzón de 1001 / 1002 |
| `500` | Prueba de eco |

## Despliegue

Hay dos métodos. Los dos usan la misma configuración de [`configs/`](configs/).

| | Máquina virtual (VirtualBox) | Docker |
|---|---|---|
| Arranque | `./vm/despliegue_asterisk.sh` | `docker compose up -d --build` |
| Aplicar cambios de `configs/` | `./vm/actualizar_config.sh <ID>` | `docker compose exec asterisk cda-recargar` |
| Guía | [docs/vm.md](docs/vm.md) | [docs/docker.md](docs/docker.md) |

Con Docker hay que indicar antes la IP del equipo en la red de los móviles:
`echo "EXTERNAL_IP=192.168.1.50" > .env` (ver [docs/docker.md](docs/docker.md)).

## Estructura

```
configs/         configuración de Asterisk, común a los dos métodos
  ├── pjsip.conf       transporte, extensiones y contraseñas
  ├── extensions.conf  plan de marcado
  ├── voicemail.conf   buzones de voz
  └── modules.conf     módulos (sin chan_sip)
vm/              despliegue en VirtualBox y sus tests
docker/          imagen Docker (Dockerfile y scripts del contenedor)
compose.yaml     arranque con Docker Compose
docs/            guías de cada método
.github/         CI (tests del script de la VM)
```
