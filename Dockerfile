FROM node:20 AS builder

ARG HAPPY_REPO=https://github.com/slopus/happy.git
ARG HAPPY_REF=main

RUN apt-get update \
    && apt-get install -y --no-install-recommends git python3 ffmpeg make g++ build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /repo
RUN git clone --depth 1 --branch "${HAPPY_REF}" "${HAPPY_REPO}" /repo

RUN corepack enable
RUN yarn install --frozen-lockfile --ignore-engines
RUN yarn workspace @slopus/happy-wire build
RUN yarn workspace happy-server build

FROM node:20 AS runner

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 ffmpeg \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /repo

ENV NODE_ENV=production \
    DB_PROVIDER=pglite \
    DATA_DIR=/data \
    PGLITE_DIR=/data/pglite \
    PORT=3005

COPY --from=builder /repo/node_modules /repo/node_modules
COPY --from=builder /repo/packages/happy-wire /repo/packages/happy-wire
COPY --from=builder /repo/packages/happy-server /repo/packages/happy-server

VOLUME ["/data"]
EXPOSE 3005

CMD ["sh", "-lc", "yarn --cwd packages/happy-server standalone migrate && exec yarn --cwd packages/happy-server standalone serve"]
