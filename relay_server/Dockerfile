# syntax=docker/dockerfile:1

########## Build stage ##########
FROM node:22-bookworm-slim AS build
WORKDIR /app

# sharp needs build tooling at install time for its native binding.
# (SQLite access uses Node's built-in node:sqlite - no better-sqlite3, no
# native compilation needed for storage.)
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 make g++ \
    && rm -rf /var/lib/apt/lists/*

COPY package.json package-lock.json* ./
RUN npm install

COPY tsconfig.json ./
COPY src ./src
RUN npm run build

# Prune dev dependencies for the runtime image.
RUN npm prune --omit=dev

########## Runtime stage ##########
FROM node:22-bookworm-slim AS runtime
WORKDIR /app
ENV NODE_ENV=production

# Runtime libs required by sharp (libvips) - node:bookworm images already ship
# the glibc runtime sharp's prebuilt binaries need; curl is used by the healthcheck.
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 1001 photoframe \
    && useradd --system --uid 1001 --gid photoframe --home-dir /app --shell /usr/sbin/nologin photoframe

COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY package.json ./
COPY public ./public
# dist/db/migrations/*.sql and dist/db/schema.sql are already produced by
# `npm run build` (see package.json copy:sql) and included via the dist copy
# above - the migration loader reads them from __dirname at runtime.

RUN mkdir -p /data/blobs /data/backups && chown -R photoframe:photoframe /app /data

USER photoframe

EXPOSE 8080
VOLUME ["/data"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD curl -fsS http://127.0.0.1:8080/healthz || exit 1

CMD ["node", "--experimental-sqlite", "dist/index.js"]
