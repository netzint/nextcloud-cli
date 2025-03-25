#!/bin/bash
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ db:add-missing-indices