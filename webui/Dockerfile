# webui — Quarkus + Vaadin web UI and calendar feed for Blindensport Graz.
#
# Build context is webui/ (docker-compose.yml does this):
#   docker build -t webui webui/
#   podman build -t webui webui/
#
# Speaks plain HTTP on 8080 and must only be reached through the TLS proxy
# (Caddy in docker-compose.yml, or an existing Traefik via compose.traefik.yml)
# — see webui/README.md "Deployment".

# ================================
# Build image
# ================================
# Pinned by digest so a rebuild uses the same base; Dependabot proposes
# updates (.github/dependabot.yml).
FROM maven:3.9-eclipse-temurin-21@sha256:99e61abcff91a9b1333463bd8451fb18495d6eba9250ac66a338b518f8278320 AS build
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
FROM eclipse-temurin:21-jre@sha256:d77e090ae1f6970c047b443c6f0a6c1358b0426d44432bb5a7753408cd43de0d

RUN useradd --user-group --create-home --system --home-dir /app webui
WORKDIR /app
COPY --from=build --chown=webui:webui /build/target/quarkus-app/ ./
USER webui:webui

EXPOSE 8080
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "-jar", "quarkus-run.jar"]
