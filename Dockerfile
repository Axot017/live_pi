ARG ELIXIR_VERSION=1.18.4
ARG OTP_VERSION=27

FROM elixir:${ELIXIR_VERSION}-otp-${OTP_VERSION} AS builder

RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential git ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config ./config
RUN mix deps.get --only ${MIX_ENV}
RUN mix deps.compile

COPY lib ./lib
COPY priv ./priv
COPY assets ./assets

RUN mix compile
RUN mix assets.deploy
RUN mix release

FROM debian:bookworm-slim AS app

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      git \
      libncurses6 \
      libstdc++6 \
      locales \
      openssl && \
    rm -rf /var/lib/apt/lists/* && \
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    HOME=/app \
    MIX_ENV=prod \
    PHX_SERVER=true \
    PORT=4000 \
    LIVE_PI_PROJECTS_DIR=/projects \
    LIVE_PI_PI_EXECUTABLE=pi

WORKDIR /app
RUN mkdir -p /projects

COPY --from=builder /app/_build/prod/rel/live_pi ./

EXPOSE 4000

CMD ["/app/bin/live_pi", "start"]
