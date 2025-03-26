#!/bin/bash
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ db:add-missing-indices
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ maintenance:repair
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ maintenance:mimetype:update-db
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ maintenance:mimetype:update-js
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ maintenance:repair --include-expensive