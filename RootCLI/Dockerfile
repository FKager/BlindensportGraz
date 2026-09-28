# clubmembersapi — Vapor web server + admin webui for the Grazer VSC roster.
#
# Build context must be the REPOSITORY ROOT, not RootCLI/, because
# RootCLI/Package.swift depends on the sibling package at ../Shared/ClubSchema
# (see Package.swift's `.package(path: "../Shared/ClubSchema")`):
#
#   docker build -f RootCLI/Dockerfile -t clubmembersapi .
#   podman build -f RootCLI/Dockerfile -t clubmembersapi .
#
# See RootCLI/README.md "Deployment / TLS" for required environment
# variables and the mandatory TLS-terminating reverse proxy in front of this
# container — it speaks plain HTTP and must never be exposed directly.

# ================================
# Build image
# ================================
FROM swift:6.0-jammy AS build

WORKDIR /build

# Resolve dependencies first so they're cached separately from source changes.
COPY RootCLI/Package.swift RootCLI/Package.swift
COPY Shared/ClubSchema/Package.swift Shared/ClubSchema/Package.swift
RUN cd RootCLI && swift package resolve

# Now copy full sources and build.
COPY RootCLI RootCLI
COPY Shared/ClubSchema Shared/ClubSchema

WORKDIR /build/RootCLI
RUN swift build -c release --product clubmembersapi --static-swift-stdlib

# Stage the runtime artifacts (binary + static webui) in one place.
RUN mkdir -p /staging \
    && cp "$(swift build -c release --product clubmembersapi --static-swift-stdlib --show-bin-path)/clubmembersapi" /staging/ \
    && cp -R /build/RootCLI/Public /staging/Public

# ================================
# Run image
# ================================
FROM swift:6.0-jammy-slim

RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update \
    && apt-get -q dist-upgrade -y \
    && apt-get -q install -y --no-install-recommends ca-certificates tzdata \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --user-group --create-home --system --home-dir /app clubmembersapi

WORKDIR /app
COPY --from=build --chown=clubmembersapi:clubmembersapi /staging/clubmembersapi ./clubmembersapi
COPY --from=build --chown=clubmembersapi:clubmembersapi /staging/Public ./Public

USER clubmembersapi:clubmembersapi

# Vapor binds 127.0.0.1 by default (see Configure.swift), which is
# unreachable from outside the container's network namespace — override to
# listen on all interfaces inside the container. The host/proxy in front of
# it is what actually restricts external reachability.
ENV HOSTNAME=0.0.0.0
ENV PORT=8080
EXPOSE 8080

ENTRYPOINT ["./clubmembersapi"]
CMD ["serve"]
