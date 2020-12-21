#!/bin/bash -x

# NOTE: Startup Script is run once / initialization only (Cloud-Init behavior vs. typical re-entrant for Azure Custom Script Extension )
# For 15.1+ and above, Cloud-Init will run the script directly and can remove Azure Custom Script Extension 

# Send output to log file and serial console
mkdir -p  /var/log/cloud /config/cloud /var/config/rest/downloads
LOG_FILE=/var/log/cloud/startup-script.log
[[ ! -f $LOG_FILE ]] && touch $LOG_FILE || { echo "Run Only Once. Exiting"; exit; }
npipe=/tmp/$$.tmp
trap "rm -f $npipe" EXIT
mknod $npipe p
tee <$npipe -a $LOG_FILE /dev/ttyS0 &
exec 1>&-
exec 1>$npipe
exec 2>&1

BIGIP_USERNAME='${bigip_username}'
BIGIP_PASSWORD='${bigip_password}'

# Adding bigip user and password 

user_status=`tmsh list auth user $BIGIP_USERNAME`
if [[ $user_status != "" ]]; then
   response_status=`tmsh modify auth user $BIGIP_USERNAME password $BIGIP_PASSWORD`
   echo "Response Code for setting user and password:$response_status"
fi
if [[ $user_status == "" ]]; then
   response_status=`tmsh create auth user $BIGIP_USERNAME password $BIGIP_PASSWORD partition-access add { all-partitions { role admin } }`
   echo "Response Code for setting user and password:$response_status"
fi

### write_files:
# Download or Render BIG-IP Runtime Init Config 
cat << 'EOF' > /config/cloud/runtime-init-conf.yaml

runtime_parameters:
  - name: ADMIN_PASS
    type: secret
    secretProvider:
      environment: azure
      type: KeyVault
      vaultUrl: ${vault_uri}
      secretId: ${secret_id}
pre_onboard_enabled:
  - name: provision_rest
    type: inline
    commands:
      - /usr/bin/setdb provision.extramb 500
      - /usr/bin/setdb restjavad.useextramb true
extension_packages:
    install_operations:
        - extensionType: do
          extensionVersion: 1.16.0
        - extensionType: as3
          extensionVersion: 3.23.0
        - extensionType: ts
          extensionVersion: 1.12.0
        - extensionType: cf
          extensionVersion: 1.6.1
extension_services:
  service_operations:
    - extensionType: do
      type: url
      value: https://raw.githubusercontent.com/F5Networks/f5-bigip-runtime-init/main/examples/declarations/do_w_admin.json
    - extensionType: as3
      type: url
      value: https://raw.githubusercontent.com/F5Networks/f5-bigip-runtime-init/main/examples/declarations/as3.json
post_onboard_enabled: []

EOF

### runcmd:
# Download
PACKAGE_URL='https://cdn.f5.com/product/cloudsolutions/f5-bigip-runtime-init/v1.1.0/dist/f5-bigip-runtime-init-1.1.0-1.gz.run'
for i in {1..30}; do
    curl -fv --retry 1 --connect-timeout 5 -L $PACKAGE_URL -o "/var/config/rest/downloads/f5-bigip-runtime-init-1.1.0-1.gz.run" && break || sleep 10
done
# Install
bash /var/config/rest/downloads/f5-bigip-runtime-init-1.1.0-1.gz.run -- '--cloud azure'
# Run
f5-bigip-runtime-init --config-file /config/cloud/runtime-init-conf.yaml
