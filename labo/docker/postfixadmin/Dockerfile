# =============================================================================
# PostfixAdmin — administration des domaines et des boites du stack Docker.
# Version epinglee ; le docroot est public/ depuis la 3.3.
# =============================================================================
FROM php:8.1-apache

ARG PFA_VERSION=3.3.13

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl gettext-base \
      libpng-dev libjpeg62-turbo-dev libfreetype6-dev libzip-dev libicu-dev libonig-dev \
 && docker-php-ext-configure gd --with-freetype --with-jpeg \
 && docker-php-ext-install -j"$(nproc)" pdo_mysql gd intl zip \
 && a2enmod rewrite \
 && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /tmp/pfa.tar.gz \
      "https://github.com/postfixadmin/postfixadmin/archive/refs/tags/postfixadmin-${PFA_VERSION}.tar.gz" \
 && tar -xzf /tmp/pfa.tar.gz -C /tmp \
 && mv "/tmp/postfixadmin-postfixadmin-${PFA_VERSION}" /var/www/postfixadmin \
 && rm -f /tmp/pfa.tar.gz \
 && mkdir -p /var/www/postfixadmin/templates_c \
 && chown -R www-data:www-data /var/www/postfixadmin/templates_c

COPY docker/postfixadmin/config.local.php.template /opt/postfixadmin/config.local.php.template
COPY docker/postfixadmin/apache.conf                /etc/apache2/sites-available/postfixadmin.conf
COPY docker/postfixadmin/entrypoint.sh              /usr/local/bin/entrypoint.sh

RUN chmod 0755 /usr/local/bin/entrypoint.sh \
 && a2dissite 000-default \
 && a2ensite postfixadmin

EXPOSE 80

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
