ARG MIX_ENV="prod"

### Build stage ###

FROM elixir:1.19-otp-28-alpine AS build

RUN apk add --no-cache git gcc g++ musl-dev make cmake postgresql-client nodejs npm

ARG MIX_ENV
ENV MIX_ENV="${MIX_ENV}"

WORKDIR /opt/revix

RUN mix local.hex --force && \
    mix local.rebar --force

COPY VERSION.default VERSION.full
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV

RUN mkdir config
COPY config/config.exs config/$MIX_ENV.exs config/
RUN mix deps.compile

# Install npm packages early for better caching
COPY assets/package.json assets/package-lock.json ./assets/
RUN cd assets && npm ci --progress=false --no-audit --loglevel=error

COPY priv priv
COPY assets assets
COPY lib lib
COPY .git .git
COPY Makefile VERSION ./
RUN make write-version
RUN mix assets.deploy && \
    mix compile

COPY config/runtime.exs config/
RUN mix phx.gen.release && \
    mix release

### Distribute stage ###

FROM alpine AS dist

ARG MIX_ENV

RUN apk --no-cache add postgresql-client libstdc++ openssl ncurses-libs imagemagick imagemagick-jpeg imagemagick-heic

RUN addgroup -g 1000 revix && \
    adduser -u 1000 -G revix -D -h /opt/revix revix

COPY --from=build --chown=revix:revix /opt/revix/_build/$MIX_ENV/rel/revix /opt/revix
COPY --chown=revix:revix ./docker-entrypoint.sh /opt/revix/docker-entrypoint.sh

USER revix

WORKDIR /opt/revix

EXPOSE 4000

ENTRYPOINT ["./docker-entrypoint.sh"]
