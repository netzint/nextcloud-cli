#!/bin/bash

source nextcloud.env
docker exec -it nextcloud-fpm php /var/www/html/occ db:convert-type --all-apps --clear-schema --password=${POSTGRES_PASSWORD} pgsql ${POSTGRES_USER} ${POSTGRES_HOST} ${POSTGRES_DB}