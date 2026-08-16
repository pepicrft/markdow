ARG ELIXIR_VERSION=1.20.1
ARG OTP_VERSION=29.0.2
ARG DEBIAN_VERSION=trixie-20260610-slim

ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="docker.io/debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mkdir config
COPY config/config.exs config/prod.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib
RUN mix compile

COPY config/runtime.exs config/
RUN mix release

FROM ${RUNNER_IMAGE} AS final

LABEL org.opencontainers.image.source="https://github.com/pepicrft/markdow"

# chromium and the font packages render the Open Graph cards through the
# browse_chrome pool. tini reaps the browser's child processes so they do not
# accumulate as zombies inside the container.
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates libncurses6 libstdc++6 locales openssl \
    chromium fontconfig fonts-liberation tini \
  && rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8
ENV MIX_ENV=prod
ENV MARKDOW_SERVER=true

WORKDIR /app
RUN mkdir -p /app/data && chown -R nobody:nogroup /app

COPY --from=builder --chown=nobody:root /app/_build/prod/rel/markdow ./

USER nobody

# tini is the init process that reaps the headless browser's child processes.
ENTRYPOINT ["/usr/bin/tini", "--"]

CMD ["/app/bin/markdow", "start"]
