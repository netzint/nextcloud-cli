#!/bin/bash

source ldap.env
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ ldap:delete-config s01
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ ldap:create-empty-config
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ ldap:set-config s01 hasMemberOfFilterSupport       1
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ ldap:set-config s01 ldapAgentName                  $LDAPBINDUSER
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ ldap:set-config s01 ldapAgentPassword              $LDAPBINDPW
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ ldap:set-config s01 ldapBase                       $LDAPBASEDN
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ ldap:set-config s01 ldapConfigurationActive        1
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ ldap:set-config s01 ldapEmailAttribute             mail
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ ldap:set-config s01 ldapExperiencedAdmin           0
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ ldap:set-config s01 ldapExpertUsernameAttr         sAMAccountName
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ ldap:set-config s01 ldapExtStorageHomeAttribute    sophomorixIntrinsic2
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ ldap:set-config s01 ldapGidNumber                  gidNumber
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ ldap:set-config s01 ldapGroupDisplayName           cn
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ ldap:set-config s01 ldapGroupFilter                $LDAPGROUPFILTER
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ ldap:set-config s01 ldapGroupFilterObjectclass     group
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ ldap:set-config s01 ldapGroupMemberAssocAttr       member
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ ldap:set-config s01 ldapHost                       $LDAPHOST
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ ldap:set-config s01 ldapLoginFilter                '(&(&(|(objectclass=person)))(samaccountname=%uid))'
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ ldap:set-config s01 ldapLoginFilterEmail           0
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ ldap:set-config s01 ldapLoginFilterMode            0
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ ldap:set-config s01 ldapLoginFilterUsername        1
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ ldap:set-config s01 ldapMatchingRuleInChainState   ldapMatchingRuleInChainState
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ ldap:set-config s01 ldapNestedGroups               0
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ ldap:set-config s01 ldapPagingSize                 500
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ ldap:set-config s01 ldapPort                       $LDAPPORT
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ ldap:set-config s01 ldapTLS                        0
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ ldap:set-config s01 ldapUserAvatarRule             default
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ ldap:set-config s01 ldapUserDisplayName            displayname
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ ldap:set-config s01 ldapUserFilter                 '(&(|(objectclass=person))(!(sophomorixAdminClass=attic))(|(sophomorixRole=teacher)(sophomorixRole=student)(sophomorixRole=examuser)(sophomorixRole=globaladministrator)(sophomorixRole=schooladministrator)))'
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ ldap:set-config s01 ldapUserFilterMode             1
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ ldap:set-config s01 ldapUserFilterObjectclass      person
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ ldap:set-config s01 ldapUuidGroupAttribute         auto
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ ldap:set-config s01 ldapUuidUserAttribute          auto
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ ldap:set-config s01 turnOffCertCheck               0
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ ldap:set-config s01 turnOnPasswordChange           0
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ ldap:set-config s01 useMemberOfToDetectMembership  1
docker exec --user www-data -it nextcloud-fpm /var/www/html/occ config:system:set skeletondirectory --value=""
