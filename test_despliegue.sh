#!/bin/bash
set -euo pipefail

DIR_SCRIPT=$(dirname "$(realpath "$0")")
SCRIPT_DESPLIEGUE="$DIR_SCRIPT/despliegue_asterisk.sh"
MODO="${1:---e2e}"
TEST_ID="${TEST_ID:-TEST}"
TEST_IP="${TEST_IP:-}"
MV_TEST="ASTERISK_$TEST_ID"
KEEP_VM="${KEEP_VM:-0}"

if ! command -v VBoxManage >/dev/null 2>&1 && [ -d "/c/Program Files/Oracle/VirtualBox" ]; then
  export PATH="$PATH:/c/Program Files/Oracle/VirtualBox"
fi
export MSYS_NO_PATHCONV=1

if [ -z "${LANG:-}" ] || [ "${LANG:-}" = "C" ] || [ "${LANG:-}" = "POSIX" ]; then
  if [ "$(uname -s)" = "Darwin" ]; then
    export LANG=en_US.UTF-8
  else
    export LANG=C.UTF-8
  fi
fi

PASS=0
FAIL=0

ok() {
  echo "  [OK] $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "  [FAIL] $1" >&2
  FAIL=$((FAIL + 1))
}

resumen_final() {
  echo "=================================================================="
  echo " Resumen: $PASS pruebas superadas, $FAIL fallidas"
  echo "=================================================================="
  [ "$FAIL" -eq 0 ]
}

limpiar_vm() {
  [ "$MODO" = "--e2e" ] || return 0
  if [ "$KEEP_VM" = "1" ]; then
    echo ">> Conservando máquina $MV_TEST (KEEP_VM=1)."
    return 0
  fi
  if VBoxManage list runningvms 2>/dev/null | tr -d '\r' | grep -q "\"$MV_TEST\""; then
    echo ">> Apagando máquina de prueba $MV_TEST..."
    VBoxManage controlvm "$MV_TEST" poweroff >/dev/null 2>&1 || true
    sleep 2
  fi
  if VBoxManage list vms 2>/dev/null | tr -d '\r' | grep -q "\"$MV_TEST\""; then
    echo ">> Eliminando máquina de prueba $MV_TEST..."
    VBoxManage unregistervm "$MV_TEST" --delete >/dev/null 2>&1 || true
  fi
}

trap limpiar_vm EXIT

echo "=================================================================="
echo " Test de validación ($MODO): despliegue_asterisk.sh"
echo " Host: $(uname -s) $(uname -m) ($(hostname))"
echo "=================================================================="

if [ "$MODO" = "--ci-guest" ]; then
  echo "1. Probando COMANDOS_INSTALACION y configuración de Asterisk en Debian real..."
  if grep -q "bookworm" /etc/os-release 2>/dev/null; then
    apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      wget gnupg ca-certificates libxml2 libxslt1.1 libsqlite3-0 libjansson4 libedit2 libuuid1 libcurl4
  fi
  COMANDOS_INSTALACION=$(sed -n "/^  cat <<'EOF'$/,/^EOF$/p" "$SCRIPT_DESPLIEGUE" | sed '1d;$d')

  if bash -c "$COMANDOS_INSTALACION"; then
    ok "COMANDOS_INSTALACION ejecutado correctamente"
  else
    fail "Fallo al ejecutar COMANDOS_INSTALACION"
  fi

  cp -f "$DIR_SCRIPT/configs/"* /etc/asterisk/
  chown -R asterisk:asterisk /etc/asterisk /var/lib/asterisk /var/spool/asterisk /var/log/asterisk /var/run/asterisk 2>/dev/null || true

  if /usr/sbin/asterisk; then
    ok "Demonio Asterisk iniciado correctamente"
  else
    fail "Fallo al iniciar el demonio Asterisk"
  fi

  if [ -f /etc/asterisk/pjsip.conf ] && [ -d /var/lib/asterisk/sounds/es ]; then
    ok "Fichero pjsip.conf y enlace de sonidos en español (/var/lib/asterisk/sounds/es) verificados"
  else
    fail "Falta pjsip.conf o el enlace /var/lib/asterisk/sounds/es"
  fi

  LOADED=0
  for _ in $(seq 1 15); do
    if asterisk -rx "pjsip show endpoints" 2>/dev/null | grep -q "1001" &&
       asterisk -rx "pjsip show transports" 2>/dev/null | grep -q "0.0.0.0:5060"; then
      LOADED=1
      break
    fi
    sleep 1
  done

  if [ "$LOADED" -eq 1 ]; then
    ok "Endpoint PJSIP 1001 y transporte UDP 0.0.0.0:5060 activos"
  else
    fail "Endpoint 1001 o transporte UDP 5060 no disponibles en Asterisk"
  fi

  resumen_final
  exit $?
fi

if [ "$MODO" = "--ci-host" ]; then
  VBoxManage() {
    case "${1:-} ${2:-}" in
      "list bridgedifs")
        printf "Name:            eth0\r\nIPAddress:       192.168.1.50\r\nNetworkMask:     255.255.255.0\r\nStatus:          Up\r\n\r\n"
        ;;
      "--version ")
        echo "7.2.22_MOCK"
        ;;
    esac
  }
fi

echo "1. Validación sintáctica y de herramientas..."
if bash -n "$SCRIPT_DESPLIEGUE"; then
  ok "Sintaxis Bash válida en despliegue_asterisk.sh"
else
  fail "Error de sintaxis en despliegue_asterisk.sh"
fi

if [ "$MODO" = "--ci-host" ] || command -v VBoxManage >/dev/null 2>&1; then
  ok "VBoxManage disponible ($(VBoxManage --version | tr -d '\r'))"
else
  fail "VBoxManage no encontrado"
  exit 1
fi

echo "2. Pruebas unitarias de funciones de red..."
eval "$(awk '/^listar_interfaces\(\)/,/^if \[ ! -e "\$DIR_BASE"/' "$SCRIPT_DESPLIEGUE" | sed '$d')"

if es_ip "192.168.0.222" && es_ip "10.47.75.222" && es_ip "0.0.0.0" && es_ip "255.255.255.255"; then
  ok "es_ip acepta direcciones IPv4 válidas"
else
  fail "es_ip rechazó una IPv4 válida"
fi

if ! es_ip "256.0.0.1" && ! es_ip "192.168.1" && ! es_ip "abc.def.ghi.jkl" && ! es_ip ""; then
  ok "es_ip rechaza direcciones IPv4 inválidas"
else
  fail "es_ip aceptó una IPv4 inválida"
fi

if [ "$(mascara_a_prefijo 255.255.255.0)" = "24" ] &&
   [ "$(mascara_a_prefijo 255.255.0.0)" = "16" ] &&
   [ "$(mascara_a_prefijo 255.255.255.128)" = "25" ] &&
   [ "$(mascara_a_prefijo 0.0.0.0)" = "24" ] &&
   [ "$(mascara_a_prefijo "")" = "24" ]; then
  ok "mascara_a_prefijo convierte máscaras a CIDR correctamente"
else
  fail "mascara_a_prefijo devolvió un prefijo inesperado"
fi

SALIDA_IFACES=$(listar_interfaces)
if [ -n "$SALIDA_IFACES" ] && ! printf '%s' "$SALIDA_IFACES" | grep -q $'\r'; then
  ok "listar_interfaces devuelve interfaces sin retornos de carro (CRLF)"
else
  fail "listar_interfaces vacío o con caracteres CR"
fi

if ip_en_uso "127.0.0.1"; then
  ok "ip_en_uso detecta 127.0.0.1 como activa"
else
  fail "ip_en_uso no detectó 127.0.0.1 como activa"
fi

if ! ip_en_uso "192.0.2.254"; then
  ok "ip_en_uso detecta 192.0.2.254 (TEST-NET) como libre"
else
  fail "ip_en_uso dio falso positivo con 192.0.2.254"
fi

if [ "$MODO" = "--ci-host" ]; then
  DIALOG=""
  INTERFAZ_BRIDGE=""
  IP_BRIDGE=""
  MASK_BRIDGE=""
  IP_BRIDGE_DEFECTO="10.47.75.222"
  seleccionar_interfaz >/dev/null
  configurar_ip_bridge <<<"192.168.1.222" >/dev/null
  if [ "$INTERFAZ_BRIDGE" = "eth0" ] && [ "$IP_BRIDGE" = "192.168.1.222" ] && [ "$MASK_BRIDGE" = "24" ]; then
    ok "seleccionar_interfaz y configurar_ip_bridge asignan interfaz, IP y máscara correctamente"
  else
    fail "Fallo en seleccionar_interfaz o configurar_ip_bridge ($INTERFAZ_BRIDGE / $IP_BRIDGE / $MASK_BRIDGE)"
  fi
  resumen_final
  exit $?
fi

echo "3. Prueba End-to-End (E2E) de despliegue de la VM ($MV_TEST)..."
limpiar_vm

NUM_IFACES=0
IDX_ACTIVA=1
I=1
while IFS='|' read -r NOMBRE ESTADO IP MASCARA; do
  [ -z "$NOMBRE" ] && continue
  NUM_IFACES=$((NUM_IFACES + 1))
  if [ "$ESTADO" = "Up" ] && [ "$IP" != "0.0.0.0" ] && [[ $IP != 169.254.* ]] && [ "$IDX_ACTIVA" -eq 1 ]; then
    IDX_ACTIVA=$I
  fi
  I=$((I + 1))
done <<<"$SALIDA_IFACES"

ejecutar_despliegue_sin_dialog() {
  PATH="/usr/bin:/bin:$PATH" bash -c '
    command() {
      if [ "${1:-}" = "-v" ] && [ "${2:-}" = "dialog" ]; then return 1; fi
      builtin command "$@"
    }
    export -f command
    "$1"
  ' _ "$SCRIPT_DESPLIEGUE"
}

if {
  if [ "$NUM_IFACES" -gt 1 ]; then
    printf "%s\n%s\n%s\n" "$TEST_ID" "$IDX_ACTIVA" "$TEST_IP"
  else
    printf "%s\n%s\n" "$TEST_ID" "$TEST_IP"
  fi
} | ejecutar_despliegue_sin_dialog; then
  ok "Ejecución inicial de despliegue_asterisk.sh completada con éxito"
else
  fail "Fallo en la ejecución inicial de despliegue_asterisk.sh"
fi

if VBoxManage list runningvms | tr -d '\r' | grep -q "\"$MV_TEST\""; then
  ok "La máquina $MV_TEST está en ejecución"
else
  fail "La máquina $MV_TEST no figura en runningvms"
fi

if VBoxManage showvminfo "$MV_TEST" --machinereadable | tr -d '\r' | grep -qE '^GuestAdditionsRunLevel=[23]'; then
  ok "GuestAdditionsRunLevel se encuentra en nivel activo (2 o 3)"
else
  fail "GuestAdditionsRunLevel no está en nivel 2 o 3"
fi

IP_CENTRALITA=$(VBoxManage guestproperty get "$MV_TEST" /DSBOX/eth/1/address 2>/dev/null | tr -d '\r' | sed -n 's/^Value: //p')
if es_ip "$IP_CENTRALITA"; then
  ok "Propiedad /DSBOX/eth/1/address registrada correctamente ($IP_CENTRALITA)"
else
  fail "Propiedad /DSBOX/eth/1/address inválida ($IP_CENTRALITA)"
fi

if VBoxManage guestcontrol "$MV_TEST" run --exe "/bin/bash" \
  --username root --password purple \
  --wait-stdout --wait-stderr \
  -- -c "systemctl is-active --quiet asterisk && test -f /etc/asterisk/pjsip.conf && test -d /var/lib/asterisk/sounds/es && ip -4 addr | grep -q '$IP_CENTRALITA' && for i in \$(seq 1 15); do asterisk -rx 'pjsip show endpoints' 2>/dev/null | grep -q '1001' && ss -ulnp | grep -q ':5060' && exit 0; sleep 1; done; exit 1"; then
  ok "Asterisk activo, sonidos ES, IP puente ($IP_CENTRALITA), puerto UDP 5060 y endpoint 1001 verificados"
else
  fail "Asterisk no está activo o la configuración PJSIP/red/sonidos no se aplicó correctamente"
fi

echo "4. Prueba de idempotencia con la VM ya en ejecución..."
if printf "%s\n" "$TEST_ID" | ejecutar_despliegue_sin_dialog; then
  ok "Re-ejecución en caliente reutilizó la IP sin pedir interfaz de nuevo"
else
  fail "Fallo en la re-ejecución de despliegue_asterisk.sh con la VM encendida"
fi

resumen_final
