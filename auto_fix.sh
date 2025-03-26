#!/bin/bash

set -a
source ./nextcloud.env
set +a

docker exec --user www-data -it nextcloud-fpm /var/www/html/occ db:add-missing-indices
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ maintenance:repair
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ maintenance:mimetype:update-db
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ maintenance:mimetype:update-js
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ maintenance:repair --include-expensive
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ config:system:set trusted_proxies 0 --value="$TRUSTED_PROXY" --type=string
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ config:system:set forwarded_for_headers 0 --value="HTTP_X_FORWARDED_FOR" --type=string
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ config:system:set maintenance_window_start --value=2 --type=integer
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ config:system:set default_phone_region --value="DE" --type=string

echo "✅ Nextcloud Konfiguration abgeschlossen."