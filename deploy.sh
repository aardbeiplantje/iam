#!/bin/bash 

export WORKSPACE=${WORKSPACE:-${BASH_SOURCE%/*}}
export APP_NAME=${APP_NAME:-iam}
export DOMAIN=${APP_DOMAIN?Need APP_DOMAIN}
export CERT_VOLUME=${APP_CERT_VOLUME:-certs-$APP_NAME}
IPV6=$(dig -6 $DOMAIN -t AAAA +short +retry=0 +tries=1)
if [ $? != 0 -o -z "$IPV6" ]; then
    echo -ne "problem looking up $DOMAIN:\n$IPV6\n"
    exit 1
fi

# Keycloak configuration
export KC_HOSTNAME=${KC_HOSTNAME?Need KC_HOSTNAME}
export KC_ADMIN_USER=${KC_ADMIN_USER:-kcadmin}
export KC_ADMIN_PASS=${KC_ADMIN_PASS:-$(openssl rand -base64 32)}

# Postgres configuration
export KC_POSTGRES_DB=${KC_POSTGRES_DB:-kcdb}
export KC_POSTGRES_USER=${KC_POSTGRES_USER:-kcuser}
export KC_POSTGRES_PASSWORD=${KC_POSTGRES_PASSWORD:-$(openssl rand -base64 32)}

# Certificate paths (point to your cert/key files)
export IAM_PROXY_HTTPS_SITE_CRT=${IAM_PROXY_HTTPS_SITE_CRT?Need IAM_PROXY_HTTPS_SITE_CRT (e.g. /path/to/auth_keycloak.crt)}
export IAM_PROXY_HTTPS_SITE_KEY=${IAM_PROXY_HTTPS_SITE_KEY?Need IAM_PROXY_HTTPS_SITE_KEY (e.g. /path/to/auth_keycloak.key)}
export KC_HTTPS_SITE_CRT=${KC_HTTPS_SITE_CRT?Need KC_HTTPS_SITE_CRT (e.g. /path/to/auth_keycloak.crt)}
export KC_HTTPS_SITE_KEY=${KC_HTTPS_SITE_KEY?Need KC_HTTPS_SITE_KEY (e.g. /path/to/auth_keycloak.key)}

# Keycloak keystore password
export KC_HTTPS_KEY_STORE_PASSWORD=${KC_HTTPS_KEY_STORE_PASSWORD:-$(openssl rand -base64 32)}

# Docker images
export DOCKER_IMAGE_KC=${DOCKER_IMAGE_KC:-local/iam/kc:latest}
export DOCKER_IMAGE_PROXY=${DOCKER_IMAGE_PROXY:-local/iam/proxy:latest}

cd $WORKSPACE || exit $?

# IPv6 networking (required)
export IPV6_SUBNET=${IPV6_SUBNET?Need IPV6_SUBNET (e.g. 2001:db8:c::1:0/120)}
export IPV6_GATEWAY=${IPV6_GATEWAY?Need IPV6_GATEWAY (e.g. 2001:db8:c::1:1)}
export IPV6_ADDRESS=${IPV6_ADDRESS?Need IPV6_ADDRESS (e.g. 2001:db8:c::1:2)}
nw_name=dmz-ipv6-${APP_NAME}

if [ "${APP_DO_CERTBOT:-0}" -eq 1 ]; then
    echo "checking for certificate"
    echo "running certbot"
    export APP_CERTBOT_MAIL=${APP_CERTBOT_MAIL?Need APP_CERTBOT_MAIL}
    docker compose down
    docker network rm dmz-${APP_NAME}-ipv6 2>/dev/null || true
    docker network create \
        --driver bridge \
        --ipv6 \
        --ipam-driver default \
        --subnet "$IPV6_SUBNET" \
        --gateway "$IPV6_GATEWAY" \
        --opt com.docker.network.bridge.gateway_mode_ipv6="routed" \
        --opt com.docker.network.container_iface_prefix="dmz" \
        --opt com.docker.network.bridge.enable_icc="true" \
        --opt com.docker.network.bridge.enable_ip_masquerade="false" \
        --opt com.docker.network.bridge.enable_ip6_masquerade="false" \
        --opt com.docker.network.bridge.inhibit_ipv4="true" \
        --opt com.docker.network.driver.mtu="1500" \
        dmz-${APP_NAME}-ipv6 || true
    docker rm -f certbot_$APP_NAME 2>/dev/null || true
    docker run \
        -p 80:80 \
        --pull=always \
        --rm \
        -e CERTBOT_MAIL="$APP_CERTBOT_MAIL" \
        --network dmz-${APP_NAME}-ipv6 \
        --ip6 $IPV6 \
        --name certbot_$APP_NAME \
        -v ${CERT_VOLUME}:/certs:rw \
        ghcr.io/aardbeiplantje/certbot/certbot:${APP_CERTBOT_TAG:-latest} \
            certonly \
                --agree-tos \
                --force-renewal \
                --domains "$DOMAIN" || exit $?
else
    echo "no certbot"
fi


echo "KC_HOSTNAME=$KC_HOSTNAME"
echo "ADMIN_USER=$KC_ADMIN_USER"
echo "POSTGRES_DB=$KC_POSTGRES_DB"

echo "building images with buildx bake"
docker buildx bake -f docker-bake.hcl local || exit $?

echo "starting with docker compose"
APP_NAME=$APP_NAME \
KC_HOSTNAME=$KC_HOSTNAME \
KC_ADMIN_USER=$KC_ADMIN_USER \
KC_ADMIN_PASS=$KC_ADMIN_PASS \
KC_POSTGRES_DB=$KC_POSTGRES_DB \
KC_POSTGRES_USER=$KC_POSTGRES_USER \
KC_POSTGRES_PASSWORD=$KC_POSTGRES_PASSWORD \
IAM_PROXY_HTTPS_SITE_CRT=$IAM_PROXY_HTTPS_SITE_CRT \
IAM_PROXY_HTTPS_SITE_KEY=$IAM_PROXY_HTTPS_SITE_KEY \
KC_HTTPS_SITE_CRT=$KC_HTTPS_SITE_CRT \
KC_HTTPS_SITE_KEY=$KC_HTTPS_SITE_KEY \
KC_HTTPS_KEY_STORE_PASSWORD=$KC_HTTPS_KEY_STORE_PASSWORD \
DOCKER_IMAGE_KC=$DOCKER_IMAGE_KC \
DOCKER_IMAGE_PROXY=$DOCKER_IMAGE_PROXY \
IPV6_SUBNET=$IPV6_SUBNET \
IPV6_GATEWAY=$IPV6_GATEWAY \
IPV6_ADDRESS=$IPV6_ADDRESS \
docker compose -f docker-compose.yml up -d
