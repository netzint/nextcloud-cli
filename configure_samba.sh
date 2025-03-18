#!/bin/bash


docker cp sambaConfig.json nextcloud-fpm:/
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ files_external:import /sambaConfig.json
