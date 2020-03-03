#!/usr/bin/env bash
set -euo pipefail

# Configurable options
DOMAIN="zt.dangmai.net"

echo "Get Zerotier names and ips"
curl -s --fail -H "Content-Type: application/json" -H "Authorization: Bearer ${ZEROTIER_AUTH_TOKEN}" https://my.zerotier.com/api/network/${ZEROTIER_NETWORK_ID}/member \
  | jq '[.[] | select(.config.authorized and .name != "" and type = "Member")]' \
  | jq -c '.[] | {name: .name, ip: .config.ipAssignments[0]}' > /tmp/zt.json

echo "Iterate through Zerotier entries and creating associated Cloudflare DNS entries"
while IFS="" read -r line || [ -n "$line" ]
do
  entry_name=$(echo "$line" | jq -r ".name += \".${DOMAIN}\" | .name")
  entry_ip=$(echo "$line" | jq -r ".ip")
  echo "Processing entry ${entry_name}"
  curl -s --fail -X GET "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${entry_name}&type=A&per_page=100" \
       -H "Authorization: Bearer ${CLOUDFLARE_AUTH_TOKEN}" \
       -H "Content-Type:application/json" > /tmp/cf.json

  cf_count=$(jq '.result_info.count' /tmp/cf.json)
  if [[ $cf_count -gt 0 ]]; then
    # Cloudflare DNS entry already exists, update if necessary
    cf_ip=$(jq -r '.result[0].content' /tmp/cf.json)
    cf_id=$(jq -r '.result[0].id' /tmp/cf.json)
    if [ "$entry_ip" != "$cf_ip" ]; then
      curl -s --fail -X PUT "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${cf_id}" \
           -H "Authorization: Bearer ${CLOUDFLARE_AUTH_TOKEN}" \
           -H "Content-Type: application/json" \
           --data "{\"type\":\"A\",\"name\":\"${entry_name}\",\"content\":\"${entry_ip}\",\"ttl\":1,\"proxied\":false}" > /tmp/status.json
    fi
  else
    # Cloudflare DNS entry does not exist, create one
    curl -s --fail -X POST "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
         -H "Authorization: Bearer ${CLOUDFLARE_AUTH_TOKEN}" \
         -H "Content-Type: application/json" \
         --data "{\"type\":\"A\",\"name\":\"${entry_name}\",\"content\":\"${entry_ip}\",\"ttl\":1,\"proxied\":false}" > /tmp/status.json
  fi
done </tmp/zt.json

rm -f /tmp/zt.json
rm -f /tmp/cf.json
rm -f /tmp/status.json