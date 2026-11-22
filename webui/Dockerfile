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
FROM maven:3.9-eclipse-temurin-26@sha256:b2c1ad85954592f9928e84327c65201f308ad9b5d8ed7d5b823717c97bf23fbb AS build
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
FROM eclipse-temurin:24-jre@sha256:8cb2387a28af84cf0db0948d9c67d4480192f4e567027a3963f145d218e8b4f2

RUN useradd --user-group --create-home --system --home-dir /app webui
WORKDIR /app
COPY --from=build --chown=webui:webui /build/target/quarkus-app/ ./
USER webui:webui

EXPOSE 8080
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "-jar", "quarkus-run.jar"]
