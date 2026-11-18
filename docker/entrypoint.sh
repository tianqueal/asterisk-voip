#!/bin/sh
# Genera la configuracion y arranca Asterisk en primer plano (PID principal).
set -eu

/usr/local/bin/cda-config

# Permite pasar argumentos extra a asterisk: docker run ... imagen -vvvvv
if [ "$#" -eq 0 ]; then
  set -- -vvv
fi

exec asterisk -f "$@"
