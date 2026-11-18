#!/bin/bash

TITULO="Trabajo grupal: Asterisk (CDA_1)"
CURSO="Centros de Datos, 2026/27"

DIR_SCRIPT=$(dirname "$(realpath "$0")")
DIR_CONFIGS=$(dirname "$DIR_SCRIPT")/configs

FICHEROS=(extensions.conf modules.conf pjsip.conf voicemail.conf)
DIR_ASTERISK=/etc/asterisk

VM_USER="root"
VM_PASS="purple"

REINICIAR=${REINICIAR:-}

if ! command -v VBoxManage >/dev/null 2>&1 && [ -d "/c/Program Files/Oracle/VirtualBox" ]; then
  export PATH="$PATH:/c/Program Files/Oracle/VirtualBox"
fi

export MSYS_NO_PATHCONV=1

# Ejecuta un comando dentro de la máquina virtual como root.
ejecutar_en_vm() {
  VBoxManage guestcontrol "$MV_ASTERISK" run --exe "/bin/bash" \
    --username "$VM_USER" --password "$VM_PASS" \
    --wait-stdout --wait-stderr \
    -- -c "$1"
}

for f in "${FICHEROS[@]}"; do
  if [ ! -f "$DIR_CONFIGS/$f" ]; then
    echo "ERROR: No se encuentra $DIR_CONFIGS/$f" >&2
    exit 1
  fi
done

# El identificador se puede pasar como argumento o variable de entorno (ID=xxx).
ID=${1:-$ID}

if [ -z "$ID" ]; then
  DIALOG=$(command -v dialog 2>/dev/null)

  if [ -z "$DIALOG" ]; then
    echo "$TITULO -- $CURSO"
    echo -n "Introducir el identificador único de la máquina (sin espacios) [+ ENTER]: "
    read -r ID
  else
    if ! "$DIALOG" --clear --title "$TITULO" --backtitle "$CURSO" \
      --inputbox "Introducir el identificador único de la máquina (sin espacios): " 8 50 2>/tmp/ID.txt; then
      clear
      echo "Operación cancelada por el usuario."
      rm -f /tmp/ID.txt
      exit 0
    fi
    clear
    ID=$(head -1 /tmp/ID.txt)
    rm -f /tmp/ID.txt
  fi
fi

ID=${ID:-CDA}

MV_ASTERISK="ASTERISK_$ID"

if ! VBoxManage list vms | grep -q "\"$MV_ASTERISK\""; then
  echo "ERROR: La máquina $MV_ASTERISK no existe. Ejecuta antes despliegue_asterisk.sh." >&2
  exit 1
fi

if ! VBoxManage list runningvms | grep -q "\"$MV_ASTERISK\""; then
  echo "ERROR: La máquina $MV_ASTERISK no está en ejecución." >&2
  exit 1
fi

if ! ejecutar_en_vm "command -v asterisk >/dev/null 2>&1"; then
  echo "ERROR: Asterisk no está instalado en $MV_ASTERISK. Ejecuta antes despliegue_asterisk.sh." >&2
  exit 1
fi

for f in "${FICHEROS[@]}"; do
  echo "Guardando copia de seguridad de $DIR_ASTERISK/$f ..."
  ejecutar_en_vm "[ ! -f $DIR_ASTERISK/$f ] || cp -f $DIR_ASTERISK/$f $DIR_ASTERISK/$f.bak"

  echo "Enviando $f a $MV_ASTERISK ..."
  if ! VBoxManage guestcontrol "$MV_ASTERISK" copyto     --username "$VM_USER"     --password "$VM_PASS"     --target-directory "$DIR_ASTERISK/"     "$(cygpath -w "$DIR_CONFIGS/$f" 2>/dev/null || echo "$DIR_CONFIGS/$f")"; then
    echo "ERROR: Fallo al copiar $f a la máquina virtual." >&2
    exit 1
  fi
done

PERMISOS=""
for f in "${FICHEROS[@]}"; do
  PERMISOS="$PERMISOS chown asterisk:asterisk $DIR_ASTERISK/$f &&"
done

# modules.conf solo se aplica al arrancar, por lo que exige reinicio.
if [ -n "$REINICIAR" ]; then
  echo "Reiniciando el servicio Asterisk ..."
  COMANDO_APLICAR="$PERMISOS systemctl restart asterisk"
else
  echo "Recargando la configuración (PJSIP, dialplan y voicemail) ..."
  COMANDO_APLICAR="$PERMISOS asterisk -rx 'module reload res_pjsip.so' && asterisk -rx 'dialplan reload' && asterisk -rx 'module reload app_voicemail.so'"
fi

if ! ejecutar_en_vm "$COMANDO_APLICAR"; then
  echo "ERROR: Fallo al aplicar la configuración en Asterisk." >&2
  echo "       Las copias anteriores quedan como *.bak en $DIR_ASTERISK" >&2
  exit 1
fi

echo "----------------------------------------------------------------"
echo "Configuración actualizada correctamente en $MV_ASTERISK:"
printf '  - %s
' "${FICHEROS[@]}"
echo "  - Copias anteriores: $DIR_ASTERISK/*.bak (en la máquina virtual)"
echo "  - Si cambias modules.conf o el bloque [transport-*], usa: REINICIAR=1 $0"
echo "----------------------------------------------------------------"
