FROM alpine:latest AS proxy-runtime
RUN apk add --no-cache \
    nginx \
    nginx-mod-http-auth-jwt \
    nginx-mod-http-headers-more \
    nginx-mod-http-lua \
    nginx-mod-http-perl \
    perl-uri \
    perl-json \
    perl-json-xs \
    curl
COPY ./nginx.conf /etc/nginx/nginx.conf
COPY ./nginx.sh /nginx.sh
RUN ln -s /certs/ /etc/nginx/certs
RUN <<EOngxtest
    PERL5LIB=""
    PERL5LIB=$PERL5LIB:/usr/lib/perl5/vendor_perl/armv8l-linux-thread-multi-64int
    PERL5LIB=$PERL5LIB:/usr/lib/perl5/vendor_perl/x86_64-linux-thread-multi
    export PERL5LIB
    nginx -t -c /etc/nginx/nginx.conf
    err=$?
    exit $err
EOngxtest
RUN mkdir -p /var/lib/nginx/logs/ && chown -R nginx:nginx /var/lib/nginx/logs/
RUN mkdir -p /run/nginx/ && chown -R nginx:nginx /run/nginx/
USER nginx
ENTRYPOINT ["/nginx.sh"]

FROM registry.access.redhat.com/ubi9 AS ubi-micro-build-cert
RUN update-ca-trust

FROM quay.io/keycloak/keycloak:latest AS builder
WORKDIR /opt/keycloak
ADD --chown=keycloak:keycloak --chmod=644 https://repo1.maven.org/maven2/org/bouncycastle/bcpkix-fips/2.0.7/bcpkix-fips-2.0.7.jar providers/bcpkix-fips-2.0.7.jar
ADD --chown=keycloak:keycloak --chmod=644 https://repo1.maven.org/maven2/org/bouncycastle/bctls-fips/2.0.19/bctls-fips-2.0.19.jar providers/bctls-fips-2.0.19.jar
ADD --chown=keycloak:keycloak --chmod=644 https://repo1.maven.org/maven2/org/bouncycastle/bc-fips/2.0.0/bc-fips-2.0.0.jar         providers/bc-fips-2.0.0.jar
ADD --chown=keycloak:keycloak --chmod=644 https://repo1.maven.org/maven2/org/bouncycastle/bcutil-fips/2.0.3/bcutil-fips-2.0.3.jar         providers/bcutil-fips-2.0.3.jar

FROM quay.io/keycloak/keycloak:latest AS kc-runtime
LABEL maintainer="CowboyTim <aardbeiplantje@gmail.com>"
LABEL org.opencontainers.image.source=https://github.com/aardbeiplantje/iam
LABEL org.opencontainers.image.authors="CowboyTim <aardbeiplantje@gmail.com>"
LABEL org.opencontainers.image.description="Keycloak with FIPS 140-2 compliant BouncyCastle"
LABEL org.opencontainers.image.licenses="unlicense"

COPY --from=builder /opt/keycloak/ /opt/keycloak/
COPY --from=ubi-micro-build-cert /etc/pki /etc/pki
COPY kc.java.security /opt/keycloak/conf
COPY --chmod=0555 --chown=root kc.sh /
ENTRYPOINT ["/kc.sh"]
