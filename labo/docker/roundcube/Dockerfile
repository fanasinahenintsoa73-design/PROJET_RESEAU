# =============================================================================
# Roundcube 1.7.x + skin meteo — image du banc d'essai.
# Le skin est copie depuis le depot au demarrage (entrypoint), pas fige dans
# l'image : un git pull + redemarrage suffit a mettre l'interface a jour.
# =============================================================================
FROM php:8.1-apache

ARG RC_VERSION=1.7.4

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl gettext-base openssl mariadb-client \
      libpng-dev libjpeg62-turbo-dev libfreetype6-dev libzip-dev \
      libicu-dev libonig-dev libxml2-dev \
 && docker-php-ext-configure gd --with-freetype --with-jpeg \
 && docker-php-ext-install -j"$(nproc)" intl pdo_mysql zip gd exif \
 && a2enmod ssl rewrite headers \
 && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /tmp/rc.tar.gz \
      "https://github.com/roundcube/roundcubemail/releases/download/${RC_VERSION}/roundcubemail-${RC_VERSION}-complete.tar.gz" \
 && tar -xzf /tmp/rc.tar.gz -C /tmp \
 && mv /tmp/roundcubemail-* /var/www/roundcube \
 && rm -f /tmp/rc.tar.gz \
 && mkdir -p /var/www/roundcube/temp /var/www/roundcube/logs \
 && chown -R www-data:www-data /var/www/roundcube/temp /var/www/roundcube/logs

# Certificat auto-signe du laboratoire (Let's Encrypt en production).
RUN mkdir -p /etc/apache2/tls \
 && openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
      -subj "/CN=webmail.meteo-test.lan" \
      -keyout /etc/apache2/tls/webmail.key \
      -out /etc/apache2/tls/webmail.pem \
 && chmod 0600 /etc/apache2/tls/webmail.key

COPY docker/roundcube/config.inc.php.template /opt/roundcube/config.inc.php.template
COPY docker/roundcube/apache-ssl.conf          /etc/apache2/sites-available/roundcube-ssl.conf
COPY docker/roundcube/entrypoint.sh            /usr/local/bin/entrypoint.sh
COPY skins/meteo                               /opt/meteo-skin

RUN chmod 0755 /usr/local/bin/entrypoint.sh \
 && a2dissite 000-default \
 && a2ensite roundcube-ssl

EXPOSE 443

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
