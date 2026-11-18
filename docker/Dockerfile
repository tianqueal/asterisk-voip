# syntax=docker/dockerfile:1.7
# =====================================================================
# Centralita Asterisk del trabajo CDA en un contenedor (alternativa a la VM)
#
#   - Base Alpine: Asterisk 20 (misma rama que la VM con Debian 12) en ~40 MB
#   - Multietapa: la descarga de locuciones y tzdata no llegan a la imagen final
#   - Se ejecuta como usuario sin privilegios (asterisk)
# =====================================================================
ARG ALPINE_VERSION=3.22

# ---------------------------------------------------------------------
# Etapa 1: recursos (locuciones en español y zona horaria de Madrid)
# ---------------------------------------------------------------------
FROM alpine:${ALPINE_VERSION} AS recursos

ARG SOUNDS_VERSION=1.6.1
ARG SOUNDS_SHA256=552e80985f6c3419a16362d9a5ae9a52351efc8f9ee251b37db6a61d36e39dfc

ADD --checksum=sha256:${SOUNDS_SHA256} \
    https://downloads.asterisk.org/pub/telephony/sounds/releases/asterisk-core-sounds-es-gsm-${SOUNDS_VERSION}.tar.gz \
    /tmp/sounds.tar.gz

# De tzdata solo se copia Europe/Madrid (voicemail.conf usa tz=madrid) y de
# los ejemplos de Asterisk solo indications.conf (tonos de llamada por pais).
RUN apk add --no-cache tzdata asterisk-sample-config \
 && mkdir -p /out/sounds/es /out/zoneinfo/Europe /out/base \
 && tar -xzf /tmp/sounds.tar.gz -C /out/sounds/es \
 && cp /usr/share/zoneinfo/Europe/Madrid /out/zoneinfo/Europe/ \
 && sed -E 's/^;?country=.*/country=es/' /etc/asterisk/indications.conf > /out/base/indications.conf

# ---------------------------------------------------------------------
# Etapa 2: imagen final
# ---------------------------------------------------------------------
FROM alpine:${ALPINE_VERSION}

LABEL org.opencontainers.image.title="asterisk-cda" \
      org.opencontainers.image.description="Centralita Asterisk (PJSIP + buzon de voz) del trabajo CDA"

# /etc/asterisk se vacia: la configuracion se genera al arrancar (cda-config)
RUN apk add --no-cache asterisk \
 && rm -rf /etc/asterisk/* /var/cache/apk/* \
 && install -d -o asterisk -g asterisk /config /var/lib/asterisk/keys

COPY --from=recursos /out/zoneinfo/ /usr/share/zoneinfo/
COPY --from=recursos /out/sounds/ /var/lib/asterisk/sounds/

# Configuracion propia del contenedor + configuracion del proyecto
COPY --from=recursos /out/base/ /usr/share/cda/base/
COPY docker/asterisk/ /usr/share/cda/base/
COPY configs/ /usr/share/cda/configs/
COPY --chmod=755 docker/cda-config docker/cda-recargar docker/entrypoint.sh /usr/local/bin/

# Se eliminan posibles CRLF (repositorio clonado en Windows)
RUN sed -i 's/\r$//' /usr/local/bin/cda-config /usr/local/bin/cda-recargar /usr/local/bin/entrypoint.sh \
 && chown -R asterisk:asterisk /etc/asterisk

ENV TZ=Europe/Madrid \
    RTP_PORT_START=10000 \
    RTP_PORT_END=10099 \
    EXTERNAL_IP="" \
    LOCAL_NET=""

USER asterisk

# 5060/udp y 5060/tcp: senalizacion SIP | 10000-10099/udp: audio/video (RTP)
EXPOSE 5060/udp 5060/tcp 10000-10099/udp

# Mensajes de los buzones de voz
VOLUME ["/var/spool/asterisk"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD asterisk -rx "core show uptime" | grep -q "System uptime" || exit 1

STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
