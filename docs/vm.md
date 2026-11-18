# Despliegue en máquina virtual (VirtualBox)

Método principal del trabajo: crea una VM Debian en VirtualBox, instala
Asterisk y copia la configuración de `configs/`.

## Requisitos

- VirtualBox 7 (`VBoxManage` en el `PATH`; en Windows se busca también en
  `C:\Program Files\Oracle\VirtualBox`).
- Bash: Git Bash en Windows, o la terminal en Linux/macOS.
- Opcional: `dialog`, para tener menús en lugar de preguntas en texto.

## Crear y arrancar la centralita

Desde la raíz del repositorio:

```bash
./vm/despliegue_asterisk.sh
```

El script:

1. Descarga (solo la primera vez) las imágenes base en `~/CDA2627`.
2. Pide un identificador y crea la VM `ASTERISK_<ID>`.
3. Pide la interfaz de red y la IP de la centralita en modo puente (por
   defecto propone la `.222` de la red del host).
4. Arranca la VM sin ventana, instala Asterisk y copia `configs/` en
   `/etc/asterisk`.

Al terminar muestra el acceso SSH (`ssh -p 2222 root@localhost`) y la IP a la
que deben conectarse los móviles (puerto 5060/UDP).

### Variables opcionales

| Variable | Descripción |
|---|---|
| `DIR_BASE` | Carpeta de las imágenes y VMs (por defecto `~/CDA2627`). |
| `INTERFAZ_BRIDGE` | Interfaz del host para el adaptador puente (evita la pregunta). |
| `IP_BRIDGE`, `MASK_BRIDGE` | IP y prefijo de la centralita (evita la pregunta). |
| `TIMEOUT_GUEST` | Espera máxima al arranque del invitado, en ms. |

Ejemplo sin preguntas de red:
`INTERFAZ_BRIDGE="Wi-Fi" IP_BRIDGE=192.168.1.222 ./vm/despliegue_asterisk.sh`

## Actualizar la configuración

Tras editar `configs/`:

```bash
./vm/actualizar_config.sh <ID>             # recarga PJSIP, dialplan y voicemail
REINICIAR=1 ./vm/actualizar_config.sh <ID> # si cambias modules.conf o el transporte
```

Guarda una copia `*.bak` de cada fichero en la VM antes de sustituirlo.

## Tests

```bash
./vm/test_despliegue.sh             # E2E: crea una VM ASTERISK_TEST real y la borra
./vm/test_despliegue.sh --ci-host   # validación del script sin VirtualBox
./vm/test_despliegue.sh --ci-guest  # instalación en un Debian real (contenedor CI)
```

Variables del E2E: `TEST_ID` (por defecto `TEST`), `TEST_IP` y `KEEP_VM=1`
para conservar la VM al terminar. La CI de GitHub ejecuta `--ci-host` en
Linux, macOS y Windows, y `--ci-guest` en Debian 11 y 12.
