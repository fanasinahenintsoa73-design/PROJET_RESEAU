# =============================================================================
# Postfix du stack Docker — Ubuntu 22.04, meme version que le labo.
# Les cartes (virtual_mailbox_maps, alias) lisent MariaDB au lieu des fichiers
# hash : aucun fichier genere a maintenir.
# =============================================================================
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Postfix refuse de s'installer sans response au debconf.
RUN echo "postfix postfix/main_mailer_type select No configuration" | debconf-set-selections \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      postfix postfix-mysql libsasl2-modules ca-certificates gettext-base openssl \
 && rm -rf /var/lib/apt/lists/*

# Certificat auto-signe du laboratoire (Let's Encrypt en production).
RUN mkdir -p /etc/postfix/tls \
 && openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
      -subj "/CN=mail.meteo-test.lan" \
      -keyout /etc/postfix/tls/postfix.key \
      -out /etc/postfix/tls/postfix.pem \
 && chown -R root:postfix /etc/postfix/tls \
 && chmod 0640 /etc/postfix/tls/postfix.key

COPY docker/postfix/main.cf.template        /etc/postfix/main.cf.template
COPY docker/postfix/master.cf.append        /etc/postfix/master.cf.append
COPY docker/postfix/sql/mailbox.cf.template /etc/postfix/sql/mailbox.cf.template
COPY docker/postfix/sql/alias.cf.template   /etc/postfix/sql/alias.cf.template
COPY docker/postfix/entrypoint.sh           /usr/local/bin/entrypoint.sh

RUN chmod 0755 /usr/local/bin/entrypoint.sh

EXPOSE 25 465 587

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
