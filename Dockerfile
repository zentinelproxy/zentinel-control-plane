# ---- Build Stage ----
ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=28.3.1
ARG DEBIAN_VERSION=bookworm-20260202-slim
ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y && \
    apt-get install -y build-essential git curl && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV=prod

# Install dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Copy compile-time config
COPY config/config.exs config/prod.exs config/
RUN mix deps.compile

# Copy application code and runtime config
COPY priv priv
COPY lib lib
COPY assets assets
COPY config/runtime.exs config/

# Compile the application (generates phoenix-colocated hooks needed by esbuild)
RUN mix compile

# Compile assets (must run after mix compile for colocated hooks)
RUN mix assets.deploy

# Build the release
RUN mix release

# ---- Runtime Stage ----
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates curl && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app

# Set runner ENV
ENV MIX_ENV=prod
ENV PHX_SERVER=true

# Copy the release from the build stage
COPY --from=builder /app/_build/prod/rel/zentinel_cp ./

# Create a non-root user
RUN groupadd -r zentinel && useradd -r -g zentinel zentinel
RUN chown -R zentinel:zentinel /app
USER zentinel

EXPOSE 4000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:4000/health || exit 1

CMD /app/bin/zentinel_cp eval "ZentinelCp.Release.migrate()" && \
    /app/bin/zentinel_cp eval "ZentinelCp.Release.seed()" && \
    /app/bin/zentinel_cp start
