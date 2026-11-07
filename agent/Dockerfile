# Agent image. It includes the zentinel binary from the proxy image, so bundles
# are checked with `zentinel test` before they are installed.
ARG ZENTINEL_IMAGE=ghcr.io/zentinelproxy/zentinel:latest

FROM golang:1.25-bookworm AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY *.go ./
ARG VERSION=dev
RUN CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X main.version=${VERSION}" -o /zentinel-cp-agent .

FROM ${ZENTINEL_IMAGE} AS proxy

FROM debian:bookworm-slim
RUN apt-get update -y && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /zentinel-cp-agent /usr/local/bin/zentinel-cp-agent
COPY --from=proxy /zentinel /usr/local/bin/zentinel

# The same user as the proxy image, so the agent may signal the proxy and the
# proxy may read the files the agent writes.
RUN groupadd -g 65532 nonroot && useradd -u 65532 -g nonroot -M -s /usr/sbin/nologin nonroot \
    && mkdir -p /etc/zentinel /var/lib/zentinel-cp-agent \
    && chown nonroot:nonroot /etc/zentinel /var/lib/zentinel-cp-agent
USER nonroot

ENV ZCP_CONFIG_DIR=/etc/zentinel \
    ZCP_STATE_DIR=/var/lib/zentinel-cp-agent \
    ZCP_VALIDATE_CMD="zentinel test -c {config}" \
    ZCP_RELOAD=process:zentinel

# Healthy once a config is installed, so the proxy can wait for one.
HEALTHCHECK --interval=5s --timeout=3s --start-period=5s \
  CMD test -s /etc/zentinel/zentinel.kdl

ENTRYPOINT ["/usr/local/bin/zentinel-cp-agent"]
