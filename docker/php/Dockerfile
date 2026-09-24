ARG PHP_VERSION=8.5
FROM php:${PHP_VERSION}-fpm

ARG UID=1000
ARG GID=1000

ADD --chmod=0755 https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/

RUN apt-get update \
    && apt-get install -y --no-install-recommends git unzip default-mysql-client \
    && rm -rf /var/lib/apt/lists/* \
    && install-php-extensions \
        bcmath \
        gd \
        intl \
        pdo_mysql \
        soap \
        sockets \
        sodium \
        xsl \
        zip \
        ftp \
        redis \
        @composer

RUN usermod -u ${UID} www-data && groupmod -g ${GID} www-data \
    && mkdir -p /home/www-data/.composer \
    && usermod -d /home/www-data www-data \
    && chown -R www-data:www-data /var/www /home/www-data

COPY php.ini /usr/local/etc/php/conf.d/zz-magento.ini

WORKDIR /var/www/html
USER www-data
