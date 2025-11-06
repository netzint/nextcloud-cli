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
docker exec --user www-data -it nextcloud-fpm bash -c 'echo "# Nextcloud data directory" > /var/www/html/data/.ncdata'
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ config:system:set login_protection_enabled --value=false
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ config:system:set brute_force_protection_enabled --value=false
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ config:system:set logtimezone --value="Europe/Berlin"
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ config:system:set overwrite.cli.url --value="$NEXTCLOUD_URL"
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ config:system:set overwriteprotocol --value="https"
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ config:system:set forwarded_for_headers 0 --value="HTTP_X_FORWARDED_FOR" --type=string

docker exec --user www-data -it nextcloud-fpm /var/www/html/occ config:system:set customcss --value="body-login .notecard { display: none; visibility : hidden; height : 0px !important; width : 0px !important; margin : 0px; padding : 0px; overflow : hidden; }" --type=string

docker exec --user www-data -it nextcloud-fpm /var/www/html/occ config:system:set allow_user_to_change_display_name --value=false
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ config:system:set allow_user_to_change_password --value=false
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ config:system:set allow_user_to_change_email_address --value=false
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ config:system:set allow_user_to_change_username --value=false


echo "✅ Nextcloud Konfiguration abgeschlossen."