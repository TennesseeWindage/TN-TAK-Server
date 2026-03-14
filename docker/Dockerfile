# TN-TAK-Server Dockerfile
# Multi-arch: linux/amd64 and linux/arm64 (Renesas RZ/V2H, RZ/V2N)
#
# TAK Server 5.5 requirements:
#   - Java 17 (Eclipse Temurin 17 used here)
#   - PostgreSQL 15 (run in a separate container; see docker-compose.yml)
#     IMPORTANT: PostgreSQL 16 will NOT work with TAK Server 5.5
#   - OpenJDK 17 packages must also be present (TAK .deb depends on them)
#
# This Dockerfile wraps the official TAK Server 5.5 release ZIP/Docker image.
# Download from: https://tak.gov/products/tak-server (registration required)
# Latest supported: takserver-docker-5.5-RELEASE-58.zip

FROM eclipse-temurin:17-jre AS base

LABEL maintainer="Tennessee Windage" \
      description="TAK Server 5.5 for LightIFF targeting computer deployments" \
      tak.version="5.5-RELEASE-58" \
      org.opencontainers.image.source="https://github.com/TennesseeWindage/TN-TAK-Server"

# Runtime dependencies
# openjdk-17-jdk-headless: required to satisfy TAK Server .deb package dependencies
# even when using Temurin as the runtime JRE
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    unzip \
    net-tools \
    openssl \
    postgresql-client \
    openjdk-17-jdk-headless \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/tak

# The TAK Server release is extracted by setup.sh into ./tak/
# That directory is bind-mounted into the container at runtime.
COPY tak/ .

# TAK Server ports:
#   8089 — CoT TCP (unencrypted; disable in CoreConfig for production)
#   8443 — HTTPS web UI + TLS CoT
#   8444 — Certificate enrollment
#   8446 — Federation (v2)
#   9000 — Federation Hub v1 broker (if fed-hub package installed)
#   9001 — Federation Hub v2 broker
EXPOSE 8089 8443 8444 8446 9000 9001

VOLUME ["/opt/tak/certs", "/opt/tak/logs", "/opt/tak/CoreConfig.xml"]

CMD ["java", "-jar", "takserver.war"]
