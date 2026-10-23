FROM mcr.microsoft.com/dotnet/sdk:8.0.404-bookworm-slim-amd64 AS build
WORKDIR /app
ENV XMAKE_ROOT=y

# Build tools. xmake is built from its official source release rather than
# installed from Debian: Debian's older xmake fails inside Docker on newer hosts
# ("wait events in poller failed"), and xmake's ready-made binary needs a newer
# system library than this image has. Building it takes a few minutes.
ARG XMAKE_VERSION=3.1.2
RUN apt-get update \
  && apt-get install -y --no-install-recommends g++ make git curl unzip ca-certificates \
  && apt-get clean \
  && curl -fsSL -o /tmp/xmake.tar.gz \
     "https://github.com/xmake-io/xmake/releases/download/v${XMAKE_VERSION}/xmake-v${XMAKE_VERSION}.tar.gz" \
  && mkdir /tmp/xmake-src && tar xzf /tmp/xmake.tar.gz -C /tmp/xmake-src --strip-components=1 \
  && cd /tmp/xmake-src && ./configure && make -j"$(nproc)" && make install \
  && cd / && rm -rf /tmp/xmake-src /tmp/xmake.tar.gz \
  && xmake --version

COPY . .

# Run through bash so xmake isn't the container's first process (PID 1), which
# handles child processes differently and can confuse xmake's process waiting.
RUN --mount=type=cache,target=/root/.xmake bash -c 'xmake -y -v; exit $?'

# RELEASE STAGE
FROM mcr.microsoft.com/dotnet/runtime:8.0.11-bookworm-slim-amd64 AS release
WORKDIR /app

COPY --from=build /app/build/linux/x86_64/release/ /app/


EXPOSE 11778
CMD [ "/app/Server.Loader" ]
