# =============================================================================
# Dovecot du stack Docker — Ubuntu 22.04.
# vmail a un UID/GID FIXE (5000) : le volume nomme reste lisible si l'image
# est reconstruite. Le stockage est le meme que celui du labo (Maildir).
# =============================================================================
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      dovecot-core dovecot-imapd dovecot-lmtpd dovecot-sieve dovecot-managesieved \
      dovecot-mysql gettext-base openssl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN groupadd -g 5000 vmail \
 && useradd -u 5000 -g vmail -d /var/vmail -s /usr/sbin/nologin vmail \
 && mkdir -p /var/vmail /var/run/dovecot /etc/dovecot/tls \
 && openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
      -subj "/CN=imap.meteo-test.lan" \
      -keyout /etc/dovecot/tls/dovecot.key \
      -out /etc/dovecot/tls/dovecot.pem \
 && chmod 0600 /etc/dovecot/tls/dovecot.key \
 && chown -R vmail:vmail /var/vmail /etc/dovecot/tls

COPY docker/dovecot/dovecot.conf               /etc/dovecot/dovecot.conf
COPY docker/dovecot/dovecot-sql.conf.template  /etc/dovecot/dovecot-sql.conf.template
COPY docker/dovecot/entrypoint.sh              /usr/local/bin/entrypoint.sh

RUN chmod 0755 /usr/local/bin/entrypoint.sh

EXPOSE 143 993

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
