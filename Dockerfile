FROM node:20 AS builder

ARG HAPPY_REPO=https://github.com/slopus/happy.git
ARG HAPPY_REF=main

RUN apt-get update \
    && apt-get install -y --no-install-recommends git curl ca-certificates python3 ffmpeg make g++ build-essential findutils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /repo
RUN git clone --depth 1 --branch "${HAPPY_REF}" "${HAPPY_REPO}" /repo

RUN corepack enable
RUN yarn config set network-timeout 600000 -g
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN yarn install --frozen-lockfile --ignore-engines --network-timeout 600000
RUN yarn workspace @slopus/happy-wire build
RUN yarn workspace happy-server build

RUN cd /repo/packages/happy-server \
    && mkdir -p dist/prisma \
    && bun build ./sources/standalone.ts \
      --compile \
      --outfile dist/happy-server \
      --target bun-linux-x64-baseline \
    && find ../../node_modules/@electric-sql/pglite/dist -name 'pglite.wasm' -exec cp {} dist/ \; \
    && find ../../node_modules/@electric-sql/pglite/dist -name 'pglite.data' -exec cp {} dist/ \; \
    && cp -r prisma/migrations dist/prisma/migrations

RUN cd /repo/packages/happy-server/dist \
    && mkdir -p /tmp/happy-smoke-data \
    && HANDY_MASTER_SECRET=smoke-test-secret \
       DATA_DIR=/tmp/happy-smoke-data \
       PGLITE_DIR=/tmp/happy-smoke-data/pglite \
       ./happy-server migrate \
    && ./happy-server --help >/dev/null

FROM debian:bookworm-slim AS runner

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates ffmpeg \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV NODE_ENV=production \
    DB_PROVIDER=pglite \
    DATA_DIR=/data \
    PGLITE_DIR=/data/pglite \
    PORT=3005

COPY --from=builder /repo/packages/happy-server/dist/ /app/

VOLUME ["/data"]
EXPOSE 3005

CMD ["sh", "-lc", "./happy-server migrate && exec ./happy-server serve"]
