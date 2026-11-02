#!/bin/bash

TITULO="Trabajo grupal: Asterisk (CDA_1)"
CURSO="Centros de Datos, 2026/27"

DIR_BASE_POR_DEFECTO=$HOME/CDA2627

URL_BASE=https://cda.drordas.info
DIR_BASE=${DIR_BASE:-$DIR_BASE_POR_DEFECTO}
DIR_VARLIB=/var/lib/CDA2627

DIR_SCRIPT=$(dirname "$(realpath "$0")")

SSH_PORT=2222
VM_USER="root"
VM_PASS="purple"

INTERFAZ_BRIDGE=$(ip route show default 2>/dev/null | awk '{ print $5 }' | head -n 1)
IP_BRIDGE=$(ip -4 -o addr show dev "$INTERFAZ_BRIDGE" 2>/dev/null | awk '{ split($4, a, "/"); sub(/\.[0-9]+$/, ".222", a[1]); print a[1]; exit }')
MASK_BRIDGE=$(ip -4 -o addr show dev "$INTERFAZ_BRIDGE" 2>/dev/null | awk '{ split($4, a, "/"); print a[2]; exit }')

COMANDOS_INSTALACION=$(
  cat <<'EOF'
set -eo pipefail

systemctl is-system-running --wait >/dev/null 2>&1 || true

if [ -f /etc/os-release ]; then
    . /etc/os-release
    DEB_VERSION="${VERSION_CODENAME:-${VERSION_ID:-unknown}}"
else
    DEB_VERSION="unknown"
fi

echo "=========================================================="
echo " Sistema operativo detectado: Debian ($DEB_VERSION)"
echo "=========================================================="

case "$DEB_VERSION" in
  bullseye|11*)
    echo ">> Configurando para Debian 11 (Bullseye)..."

    sed -i -E '/bullseye(-security|\/updates|-backports)/d' /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null || true

    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        asterisk \
        asterisk-config \
        asterisk-voicemail \
        asterisk-core-sounds-es-gsm
    ;;

  bookworm|12*)
    echo ">> Configurando para Debian 12 (Bookworm - FreePBX 17)..."
    REPO_URL="http://deb.freepbx.org/freepbx17-prod"
    REPO_LINE="deb [arch=amd64] $REPO_URL bookworm main"
    REPO_FILE="/etc/apt/sources.list.d/freepbx.list"

    wget -qO - http://deb.freepbx.org/gpg/aptly-pubkey.asc | gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/freepbx.gpg
    chmod 644 /etc/apt/trusted.gpg.d/freepbx.gpg

    echo "$REPO_LINE" > "$REPO_FILE"

    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        liburiparser1 \
        asterisk20 \
        asterisk20-core \
        asterisk20-configs \
        asterisk20-voicemail \
        asterisk-core-sounds-es-gsm
    ;;

  *)
    echo "ERROR: Versión de distribución no soportada ($DEB_VERSION)" >&2
    exit 1
    ;;
esac

mkdir -p /var/lib/asterisk/sounds
if [ -d /usr/share/asterisk/sounds/es_MX_f_Allison ]; then
    ln -sfn /usr/share/asterisk/sounds/es_MX_f_Allison /var/lib/asterisk/sounds/es
elif [ -d /usr/share/asterisk/sounds/es ]; then
    ln -sfn /usr/share/asterisk/sounds/es /var/lib/asterisk/sounds/es
fi
EOF
)

es_imagen_registrada() {
  local IMAGEN=$1
  local TIPO=$2

  VBoxManage list hdds | awk -v img="$IMAGEN" -v tipo="$TIPO" '
        BEGIN { RS = ""; FS = "\n"; ok = 0 }
        {
            location = ""; type = ""
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^Location:/) { location = $i; sub(/^Location:[ \t]*/, "", location) }
                if ($i ~ /^Type:/)     { type     = $i; sub(/^Type:[ \t]*/,     "", type) }
            }
            if (location == img && tolower(type) == tolower(tipo)) ok = 1
        }
        END { exit !ok }
    '
}

uuid_imagen() {
  local IMAGEN=$1

  VBoxManage list hdds | awk -v img="$IMAGEN" '
        BEGIN { RS = ""; FS = "\n" }
        {
            uuid = ""; location = ""
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^UUID:/)     { uuid     = $i; sub(/^UUID:[ \t]*/,     "", uuid) }
                if ($i ~ /^Location:/) { location = $i; sub(/^Location:[ \t]*/, "", location) }
            }
            if (location == img) { print uuid; exit }
        }
    '
}

registrar_imagen() {
  local DIR_BASE=$1
  local IMAGEN=$2
  local TIPO=$3
  local PUERTO=$4

  if ! VBoxManage list vms | grep -q CDA_NO_BORRAR; then
    VBoxManage createvm --name CDA_NO_BORRAR --basefolder "$DIR_BASE" --ostype Debian_64 --register
    VBoxManage storagectl CDA_NO_BORRAR --name CDA_NO_BORRAR_storage --add sata --portcount 4
  fi

  VBoxManage storageattach CDA_NO_BORRAR --storagectl CDA_NO_BORRAR_storage \
    --port "$PUERTO" --device 0 --medium none 2>/dev/null

  VBoxManage storageattach CDA_NO_BORRAR --storagectl CDA_NO_BORRAR_storage \
    --port "$PUERTO" --device 0 --type hdd --medium "$IMAGEN" --mtype normal

  VBoxManage storageattach CDA_NO_BORRAR --storagectl CDA_NO_BORRAR_storage \
    --port "$PUERTO" --device 0 --medium none

  VBoxManage storageattach CDA_NO_BORRAR --storagectl CDA_NO_BORRAR_storage \
    --port "$PUERTO" --device 0 --type hdd --medium "$IMAGEN" --mtype "$TIPO"
}

registrar_imagenes() {
  local DIR_BASE=$1
  local IMAGEN_BASE=$2
  local IMAGEN_SWAP=$3

  if ! es_imagen_registrada "$IMAGEN_BASE" "multiattach"; then
    registrar_imagen "$DIR_BASE" "$IMAGEN_BASE" "multiattach" 0
  fi

  if ! es_imagen_registrada "$IMAGEN_SWAP" "immutable"; then
    registrar_imagen "$DIR_BASE" "$IMAGEN_SWAP" "immutable" 1
  fi
}

comprobar_registro() {
  local IMAGEN_BASE=$1
  local IMAGEN_SWAP=$2

  if es_imagen_registrada "$IMAGEN_BASE" "multiattach" &&
    es_imagen_registrada "$IMAGEN_SWAP" "immutable"; then
    return 0
  fi

  local MVS
  MVS=$(VBoxManage list vms | grep -E '^"(DATOS|CDA_RAID|DISCOS|CLIENTE|CLIENTE1|CLIENTE2|APACHE1|APACHE2|BALANCEADOR|SERVIDOR1|SERVIDOR2|ASTERISK)_' | cut -d'"' -f2)

  if [ -z "$MVS" ]; then
    return 0
  fi

  echo
  echo "AVISO: las imagenes base han perdido su registro en VirtualBox."
  echo "       (lo habitual es que se haya borrado la maquina CDA_NO_BORRAR)"
  echo
  echo "Estas maquinas dependian de ellas y ya NO van a arrancar:"
  awk '{ print "  - " $0 }' <<<"$MVS"
  echo
  echo "El registro se rehace ahora, pero esas maquinas hay que borrarlas"
  echo "y volver a crearlas con su script:"
  sed 's/^/  VBoxManage unregistervm /; s/$/ --delete/' <<<"$MVS"
  echo
  echo -n "Continuar? [s/N]: "
  read -r RESP
  case "$RESP" in
  s | S | y | Y) return 0 ;;
  *)
    echo "Abortado."
    exit 1
    ;;
  esac
}

enganchar_por_uuid() {
  local MV=$1
  local CTL=$2
  local PUERTO=$3
  local IMAGEN=$4

  local UUID
  UUID=$(uuid_imagen "$IMAGEN")

  if [ -z "$UUID" ]; then
    echo "ERROR: $IMAGEN no esta registrada en VirtualBox" >&2
    return 1
  fi

  VBoxManage storageattach "$MV" --storagectl "$CTL" \
    --port "$PUERTO" --device 0 --type hdd --medium "$UUID"
}

preparar_imagen() {
  local NOMBRE_IMAGEN=$1
  local URL_BASE_ORIGEN=$2
  local DIR_BASE_DESTINO=$3

  local URL_ORIGEN="$URL_BASE_ORIGEN/$NOMBRE_IMAGEN.vdi.zip"
  local IMAGEN_DESTINO="$DIR_BASE_DESTINO/$NOMBRE_IMAGEN.vdi"

  if [ ! -e "$IMAGEN_DESTINO" ]; then
    if [ ! -e "$DIR_BASE_DESTINO/$NOMBRE_IMAGEN.vdi.zip" ]; then
      echo "Descargando imagen $URL_ORIGEN ... "
      cd "$DIR_BASE_DESTINO" || exit 1
      wget --continue "$URL_ORIGEN"
    fi
    echo "Descomprimiendo imagen $IMAGEN_DESTINO ... "
    unzip "$NOMBRE_IMAGEN.vdi.zip"
    rm "$NOMBRE_IMAGEN.vdi.zip"
  fi
}

if [ ! -e "$DIR_BASE" ]; then
  echo "Creando directorio $DIR_BASE ..."
  mkdir -p "$DIR_BASE"
fi

IMAGEN_BASE=$DIR_VARLIB/base_cda.vdi
if [ ! -e "$IMAGEN_BASE" ]; then
  IMAGEN_BASE=$DIR_BASE/base_cda.vdi
  preparar_imagen "base_cda" "$URL_BASE" "$DIR_BASE"
fi

IMAGEN_SWAP=$DIR_VARLIB/swap1GB.vdi
if [ ! -e "$IMAGEN_SWAP" ]; then
  IMAGEN_SWAP=$DIR_BASE/swap1GB.vdi
  preparar_imagen "swap1GB" "$URL_BASE" "$DIR_BASE"
fi

IMAGEN_BASE=$(realpath -m "$IMAGEN_BASE")
IMAGEN_SWAP=$(realpath -m "$IMAGEN_SWAP")

comprobar_registro "$IMAGEN_BASE" "$IMAGEN_SWAP"
registrar_imagenes "$DIR_BASE" "$IMAGEN_BASE" "$IMAGEN_SWAP"

ID=CDA
DIALOG=$(command -v dialog 2>/dev/null)

if [ -z "$DIALOG" ]; then
  echo "$TITULO -- $CURSO"
  echo -n "Introducir un identificador único (sin espacios) [+ ENTER]: "
  read -r ID
else
  if ! "$DIALOG" --clear --title "$TITULO" --backtitle "$CURSO" \
    --inputbox "Introducir un identificador único (sin espacios): " 8 50 2>/tmp/ID.txt; then
    clear
    echo "Operación cancelada por el usuario."
    rm -f /tmp/ID.txt
    exit 0
  fi
  clear
  ID=$(head -1 /tmp/ID.txt)
  rm -f /tmp/ID.txt
fi

ID=${ID:-CDA}

MV_ASTERISK="ASTERISK_$ID"
if [ ! -e "$DIR_BASE/$MV_ASTERISK" ]; then
  VBoxManage createvm --name "$MV_ASTERISK" --basefolder "$DIR_BASE" --ostype Debian_64 --register
  VBoxManage storagectl "$MV_ASTERISK" --name "${MV_ASTERISK}_storage" --add ide
  enganchar_por_uuid "$MV_ASTERISK" "${MV_ASTERISK}_storage" 0 "$IMAGEN_BASE"
  enganchar_por_uuid "$MV_ASTERISK" "${MV_ASTERISK}_storage" 1 "$IMAGEN_SWAP"
  VBoxManage modifyvm "$MV_ASTERISK" --cpus 2 --memory 1024 --pae on --vram 16 --graphicscontroller vmsvga

  VBoxManage modifyvm "$MV_ASTERISK" --nic1 nat --macaddress1 080027111111 --cableconnected1 on --nictype1 82540EM

  VBoxManage modifyvm "$MV_ASTERISK" --nat-pf1 "guestssh,tcp,,$SSH_PORT,,22"

  VBoxManage modifyvm "$MV_ASTERISK" --nic2 bridged --bridgeadapter2 "$INTERFAZ_BRIDGE" --macaddress2 080027111112 --cableconnected2 on --nictype2 82540EM

  VBoxManage modifyvm "$MV_ASTERISK" --clipboard-mode bidirectional

  VBoxManage guestproperty set "$MV_ASTERISK" /DSBOX/num_interfaces 2
  VBoxManage guestproperty set "$MV_ASTERISK" /DSBOX/eth/0/type static
  VBoxManage guestproperty set "$MV_ASTERISK" /DSBOX/eth/0/address 10.0.2.15
  VBoxManage guestproperty set "$MV_ASTERISK" /DSBOX/eth/0/netmask 24
  VBoxManage guestproperty set "$MV_ASTERISK" /DSBOX/eth/1/type static
  VBoxManage guestproperty set "$MV_ASTERISK" /DSBOX/eth/1/address "$IP_BRIDGE"
  VBoxManage guestproperty set "$MV_ASTERISK" /DSBOX/eth/1/netmask "$MASK_BRIDGE"
  VBoxManage guestproperty set "$MV_ASTERISK" /DSBOX/default_gateway 10.0.2.2
  VBoxManage guestproperty set "$MV_ASTERISK" /DSBOX/default_nameserver 8.8.8.8
  VBoxManage guestproperty set "$MV_ASTERISK" /DSBOX/host_name asterisk.cda.net
  VBoxManage guestproperty set "$MV_ASTERISK" /DSBOX/etc_hosts_dump "asterisk.cda.net:10.0.2.15"
fi

if ! VBoxManage list runningvms | grep -q "\"$MV_ASTERISK\""; then
  VBoxManage modifyvm "$MV_ASTERISK" --bridgeadapter2 "$INTERFAZ_BRIDGE"
  VBoxManage guestproperty set "$MV_ASTERISK" /DSBOX/eth/1/address "$IP_BRIDGE"
  VBoxManage guestproperty set "$MV_ASTERISK" /DSBOX/eth/1/netmask "$MASK_BRIDGE"
  VBoxManage startvm --type=headless "$MV_ASTERISK" && echo "Iniciando e instalando Asterisk en modo headless."
fi

VBoxManage guestproperty wait "$MV_ASTERISK" "/VirtualBox/GuestAdd/Version" --timeout 60000

if ! VBoxManage guestcontrol "$MV_ASTERISK" run --exe "/bin/bash" \
  --username "$VM_USER" --password "$VM_PASS" \
  -- -c "command -v asterisk >/dev/null 2>&1"; then

  if ! VBoxManage guestcontrol "$MV_ASTERISK" run --exe "/bin/bash" \
    --username "$VM_USER" --password "$VM_PASS" \
    --wait-stdout --wait-stderr \
    -- -c "$COMANDOS_INSTALACION"; then
    echo "ERROR: Fallo en la instalación de paquetes de Asterisk." >&2
    exit 1
  fi

  if [ -d "$DIR_SCRIPT/configs" ] && [ -n "$(ls -A "$DIR_SCRIPT/configs")" ]; then
    VBoxManage guestcontrol "$MV_ASTERISK" copyto -R \
      --username "$VM_USER" \
      --password "$VM_PASS" \
      --target-directory "/etc/asterisk/" \
      "$DIR_SCRIPT/configs/"*
  fi

  if ! VBoxManage guestcontrol "$MV_ASTERISK" run --exe "/bin/bash" \
    --username "$VM_USER" --password "$VM_PASS" \
    --wait-stdout --wait-stderr \
    -- -c "chown -R asterisk:asterisk /etc/asterisk /var/lib/asterisk /var/spool/asterisk && systemctl enable asterisk && systemctl restart asterisk"; then
    echo "ERROR: Fallo en el inicio del servicio Asterisk." >&2
    exit 1
  fi

  echo "Asterisk aprovisionado y configurado correctamente."
fi

echo "----------------------------------------------------------------"
echo "Servidor Asterisk activo."
echo "  - Acceso SSH (Host):     ssh -p $SSH_PORT $VM_USER@localhost"
echo "  - IP Centralita (VoIP):  $IP_BRIDGE (Puerto UDP 5060)"
echo "----------------------------------------------------------------"
