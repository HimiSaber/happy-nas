FROM node:20 AS builder

ARG HAPPY_REPO=https://github.com/slopus/happy.git
ARG HAPPY_REF=main

RUN apt-get update \
    && apt-get install -y --no-install-recommends git curl ca-certificates python3 ffmpeg make g++ build-essential findutils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /repo
RUN git clone --depth 1 --branch "${HAPPY_REF}" "${HAPPY_REPO}" /repo

# Patch upstream logging for standalone/NAS builds:
# default to plain stdout JSON logs in production instead of pino-pretty transport,
# because the pretty transport does not resolve reliably inside the compiled Bun binary.
RUN python3 - <<'PY'
from pathlib import Path
p = Path('/repo/packages/happy-server/sources/utils/log.ts')
s = p.read_text(encoding='utf-8')
old_block = """const transports: any[] = [];

// Resolve pino-pretty target - use absolute path for bundled binaries
let pinoPrettyTarget: string = 'pino-pretty';
try {
    pinoPrettyTarget = require.resolve('pino-pretty');
} catch {}

transports.push({
    target: pinoPrettyTarget,
    options: {
        colorize: true,
        translateTime: 'HH:MM:ss.l',
        ignore: 'pid,hostname',
        messageFormat: '{levelLabel} {msg} | [{time}]',
        errorLikeObjectKeys: ['err', 'error'],
    },
});
"""
new_block = """const transports: any[] = [];
const enablePrettyTransport = process.env.HAPPY_PRETTY_LOGS === 'true' || (process.env.NODE_ENV || '').trim() !== 'production';

if (enablePrettyTransport) {
    // Resolve pino-pretty target - use absolute path for bundled binaries
    let pinoPrettyTarget: string = 'pino-pretty';
    try {
        pinoPrettyTarget = require.resolve('pino-pretty');
    } catch {}

    transports.push({
        target: pinoPrettyTarget,
        options: {
            colorize: true,
            translateTime: 'HH:MM:ss.l',
            ignore: 'pid,hostname',
            messageFormat: '{levelLabel} {msg} | [{time}]',
            errorLikeObjectKeys: ['err', 'error'],
        },
    });
}
"""
if old_block not in s:
    raise SystemExit('failed to find pino-pretty transport block to patch')
s = s.replace(old_block, new_block)
old_logger = """export const logger = pino({
    level: 'debug',
    transport: {
        targets: transports,
    },
    formatters: {
        log: (object: any) => {
            // Add localTime to every log entry
            return {
                ...object,
                localTime: formatLocalTime(typeof object.time === 'number' ? object.time : undefined),
            };
        }
    },
    timestamp: () => `,\"time\":${Date.now()},\"localTime\":\"${formatLocalTime()}\"`,
});
"""
new_logger = """const loggerOptions: any = {
    level: 'debug',
    formatters: {
        log: (object: any) => {
            // Add localTime to every log entry
            return {
                ...object,
                localTime: formatLocalTime(typeof object.time === 'number' ? object.time : undefined),
            };
        }
    },
    timestamp: () => `,\"time\":${Date.now()},\"localTime\":\"${formatLocalTime()}\"`,
};

if (transports.length > 0) {
    loggerOptions.transport = {
        targets: transports,
    };
}

export const logger = pino(loggerOptions);
"""
if old_logger not in s:
    raise SystemExit('failed to find logger initialization block to patch')
s = s.replace(old_logger, new_logger)
p.write_text(s, encoding='utf-8')
print('patched', p)
PY

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

# Smoke test both migrate and serve so the image build fails if standalone runtime breaks.
# The serve smoke test runs the server in background for a few seconds:
# - if it exits early, print the captured log and fail the build
# - if it stays alive, terminate it and continue
RUN cd /repo/packages/happy-server/dist \
    && mkdir -p /tmp/happy-smoke-data \
    && HANDY_MASTER_SECRET=smoke-test-secret \
       DATA_DIR=/tmp/happy-smoke-data \
       PGLITE_DIR=/tmp/happy-smoke-data/pglite \
       HAPPY_PRETTY_LOGS=false \
       ./happy-server migrate \
    && ./happy-server --help >/dev/null \
    && HANDY_MASTER_SECRET=smoke-test-secret \
       DATA_DIR=/tmp/happy-smoke-data \
       PGLITE_DIR=/tmp/happy-smoke-data/pglite \
       HAPPY_PRETTY_LOGS=false \
       sh -lc './happy-server serve >/tmp/happy-serve.log 2>&1 & pid=$!; sleep 8; if ! kill -0 "$pid" 2>/dev/null; then cat /tmp/happy-serve.log; wait "$pid"; exit $?; fi; kill "$pid" >/dev/null 2>&1 || true; wait "$pid" >/dev/null 2>&1 || true'

FROM debian:bookworm-slim AS runner

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates ffmpeg \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV NODE_ENV=production \
    DB_PROVIDER=pglite \
    DATA_DIR=/data \
    PGLITE_DIR=/data/pglite \
    PORT=3005 \
    HAPPY_PRETTY_LOGS=false

COPY --from=builder /repo/packages/happy-server/dist/ /app/

VOLUME ["/data"]
EXPOSE 3005

CMD ["sh", "-lc", "./happy-server migrate && exec ./happy-server serve"]
