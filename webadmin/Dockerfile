# webadmin — Quarkus + Vaadin web admin and calendar feed for Blindensport Graz.
#
# Build context is webadmin/ (docker-compose.yml does this):
#   docker build -t webadmin webadmin/
#   podman build -t webadmin webadmin/
#
# Speaks plain HTTP on 8080 and must only be reached through the TLS proxy
# (Caddy in docker-compose.yml) — see webadmin/README.md "Deployment".

# ================================
# Build image
# ================================
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /build

# Dependencies first, cached separately from source changes.
COPY pom.xml .
RUN mvn -B -q dependency:resolve dependency:resolve-plugins

COPY src src
# Vaadin runs in production mode from its prebuilt bundle (core components
# only), so no Node.js is needed. Tests run in CI / locally, not here.
RUN mvn -B -q package -DskipTests

# ================================
# Run image
# ================================
FROM eclipse-temurin:21-jre

RUN useradd --user-group --create-home --system --home-dir /app webadmin
WORKDIR /app
COPY --from=build --chown=webadmin:webadmin /build/target/quarkus-app/ ./
USER webadmin:webadmin

EXPOSE 8080
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "-jar", "quarkus-run.jar"]
