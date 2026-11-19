# Despliegue en máquina virtual (VirtualBox)

Método principal del trabajo: el script crea una VM Debian en VirtualBox,
instala Asterisk dentro y copia la configuración de `configs/`. Todo el proceso
es automático; solo tienes que responder un par de preguntas.

Si prefieres no usar una VM, hay una alternativa con contenedor en
[docker.md](docker.md).

## Cómo queda la VM

| Elemento     | Valor                                                                          |
| ------------ | ------------------------------------------------------------------------------ |
| Nombre       | `ASTERISK_<ID>` (el `<ID>` lo eliges tú)                                       |
| Recursos     | 2 CPU, 1 GB de RAM, disco y swap a partir de las imágenes base de la asignatura |
| Adaptador 1  | NAT, con el puerto 2222 del host redirigido al 22 de la VM (SSH)               |
| Adaptador 2  | Puente (_bridged_), con IP fija: es la que usan los móviles                    |
| Acceso       | usuario `root`, contraseña `purple`                                            |
| Asterisk     | 20 en Debian 12, 16 en Debian 11 (según la imagen base)                        |

Los móviles y la VM deben estar en la misma red local. Por eso hace falta el
adaptador puente: con él, la VM aparece en la LAN como un dispositivo más.

## Requisitos

- VirtualBox 7, con `VBoxManage` en el `PATH`. En Windows el script también lo
  busca en `C:\Program Files\Oracle\VirtualBox`.
- Bash: Git Bash en Windows, o la terminal en Linux/macOS.
- Conexión a internet: la primera vez descarga las imágenes base y, después,
  los paquetes de Asterisk dentro de la VM.
- Opcional: `dialog`, para usar menús en lugar de preguntas en texto.

## Crear y arrancar la centralita

Desde la raíz del repositorio:

```bash
./vm/despliegue_asterisk.sh
```

El script hace lo siguiente:

1. Descarga y descomprime (solo la primera vez) las imágenes base en
   `~/CDA2627`, y las registra en VirtualBox mediante una VM auxiliar llamada
   `CDA_NO_BORRAR`.
2. Te pide un identificador y crea la VM `ASTERISK_<ID>`.
3. Te pide la interfaz de red del host para el adaptador puente (si solo hay
   una, la usa sin preguntar) y la IP de la centralita. Propone la `.222` de la
   red del host y avisa si esa IP ya responde a ping.
4. Arranca la VM sin ventana (_headless_) y espera a que el sistema invitado
   esté listo.
5. Instala Asterisk con `apt`, copia `configs/` en `/etc/asterisk` y habilita
   el servicio.

La primera ejecución tarda varios minutos por las descargas. Al terminar
muestra el acceso SSH y la IP a la que deben conectarse los móviles:

```
Servidor Asterisk activo.
  - Acceso SSH (Host):     ssh -p 2222 root@localhost
  - IP Centralita (VoIP):  192.168.1.222 (Puerto UDP 5060)
```

> **Importante:** no borres la VM `CDA_NO_BORRAR` desde VirtualBox. Las demás
> VMs dependen de las imágenes que registra. Si se pierde, el script avisa de
> qué máquinas quedan inservibles y rehace el registro.

### Variables opcionales

Puedes definirlas antes del comando para saltarte las preguntas o ajustar el
comportamiento.

| Variable                   | Descripción                                                           |
| -------------------------- | --------------------------------------------------------------------- |
| `DIR_BASE`                 | Carpeta de las imágenes y VMs (por defecto `~/CDA2627`).              |
| `INTERFAZ_BRIDGE`          | Interfaz del host para el adaptador puente (evita la pregunta).       |
| `IP_BRIDGE`, `MASK_BRIDGE` | IP y prefijo de la centralita (evita la pregunta).                    |
| `TIMEOUT_GUEST`            | Espera máxima al arranque del invitado, en ms (120 000 por defecto).  |

Ejemplo sin preguntas de red:

```bash
INTERFAZ_BRIDGE="Wi-Fi" IP_BRIDGE=192.168.1.222 ./vm/despliegue_asterisk.sh
```

En Mac con Apple Silicon la VM se ejecuta con emulación x86, así que el
arranque es mucho más lento y el tiempo de espera por defecto sube a 300 s.

## Comprobar que funciona

1. Entra en la VM y abre la consola de Asterisk:

   ```bash
   ssh -p 2222 root@localhost
   asterisk -rvvv
   ```

2. Configura un móvil (Linphone, Zoiper…) con estos datos:

   | Campo              | Valor                                       |
   | ------------------ | ------------------------------------------- |
   | Servidor / dominio | la IP de la centralita (puerto 5060, UDP)   |
   | Usuario            | `1001` o `1002`                             |
   | Contraseña         | `1234` (ver `configs/pjsip.conf`)           |

3. Comprueba el registro con `pjsip show contacts` en la consola de Asterisk y
   llama al **500** (prueba de eco) para verificar el audio en los dos sentidos.

Si el móvil no se registra, revisa que esté en la misma red que la VM y que el
cortafuegos del host no bloquee el tráfico por el adaptador puente.

## Actualizar la configuración

Tras editar `configs/`, aplica los cambios sin recrear la VM:

```bash
./vm/actualizar_config.sh <ID>             # recarga PJSIP, dialplan y voicemail
REINICIAR=1 ./vm/actualizar_config.sh <ID> # si cambias modules.conf o el transporte
```

El `<ID>` es el que elegiste al crear la VM. La VM debe estar encendida. El
script copia `extensions.conf`, `modules.conf`, `pjsip.conf` y `voicemail.conf`,
y guarda antes una copia `*.bak` de cada fichero en `/etc/asterisk` de la VM, por
si necesitas volver atrás.

Para los cambios en `modules.conf` o en los bloques `[transport-*]` no basta la
recarga: usa `REINICIAR=1`.

## Operaciones habituales

```bash
VBoxManage controlvm ASTERISK_<ID> acpipowerbutton   # apagar la VM
./vm/despliegue_asterisk.sh                          # volver a encenderla (mismo ID)
VBoxManage unregistervm ASTERISK_<ID> --delete       # borrarla del todo
```

Si vuelves a ejecutar el despliegue con un `<ID>` que ya existe, el script
reutiliza la VM: la arranca si está apagada y omite la instalación si Asterisk
ya está instalado. Si la IP o la interfaz de red del host han cambiado, indícalas
(con las variables de arriba o respondiendo a las preguntas) y se aplican al
arrancar.

## Tests

```bash
./vm/test_despliegue.sh             # E2E: crea una VM ASTERISK_TEST real y la borra
./vm/test_despliegue.sh --ci-host   # validación del script sin VirtualBox
./vm/test_despliegue.sh --ci-guest  # instalación en un Debian real (contenedor CI)
```

Variables del E2E: `TEST_ID` (por defecto `TEST`), `TEST_IP` y `KEEP_VM=1`
para conservar la VM al terminar. La CI de GitHub ejecuta `--ci-host` en
Linux, macOS y Windows, y `--ci-guest` en Debian 11 y 12.

## Solución de problemas

| Síntoma                                         | Causa probable                                                                                                  |
| ----------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `VBoxManage: command not found`                 | VirtualBox no está en el `PATH`. Añádelo o abre una terminal nueva tras instalarlo.                             |
| «Tiempo de espera agotado» al arrancar          | El invitado tarda más de lo previsto. Sube `TIMEOUT_GUEST` (por ejemplo, `TIMEOUT_GUEST=300000`).               |
| Los móviles no alcanzan la centralita           | La IP elegida está ocupada, o no pertenece a la red del host. Vuelve a ejecutar el script con otra `IP_BRIDGE`. |
| Aviso de imágenes base sin registro             | Se borró `CDA_NO_BORRAR`. Borra las VMs que lista el aviso y recréalas con su script.                           |
| Los cambios de `configs/` no se aplican         | Ejecuta `actualizar_config.sh`; para `modules.conf` o el transporte, añade `REINICIAR=1`.                       |
