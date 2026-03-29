# happy-nas

Minimal wrapper repository for building a Synology/NAS-friendly Happy Server image via GitHub Actions and publishing it to GHCR.

## What this repo does

- Builds an image for `linux/amd64` (x86 NAS / Synology)
- Clones the upstream `slopus/happy` repository during image build
- Builds **Happy Server standalone executable** instead of shipping full runtime `node_modules`
- Packages only the compiled server binary plus required runtime assets (`pglite.wasm`, `pglite.data`, Prisma migrations)
- Provides a simple Synology-friendly `compose.yaml`

## Why this wrapper exists

Synology Container Manager is happiest when it only has to pull an image.
This repo moves all building into GitHub Actions, then publishes:

- `ghcr.io/himisaber/happy-server:latest`
- `ghcr.io/himisaber/happy-server:main`

The runtime image is based on a compiled standalone binary, so it avoids copying the whole monorepo workspace dependency tree into the final image.

## Build details

- Upstream source: `https://github.com/slopus/happy`
- Build target: `bun-linux-x64-baseline`
  - baseline is used intentionally for better compatibility with older x86 NAS CPUs
- Runtime still includes:
  - `ffmpeg`
  - `ca-certificates`
  - Happy Server standalone binary
  - `pglite.wasm`
  - `pglite.data`
  - Prisma migrations

## How to update Happy Server

1. Open **Actions** in this repo
2. Run **build-and-push-happy-server**
3. Fill `happy_ref`, e.g. `main` or a specific upstream tag/branch
4. Wait for GHCR image to finish publishing
5. On NAS, redeploy using `compose.yaml`

## First deployment on Synology / NAS

- Create `/volume1/docker/happy/data`
- Copy `compose.yaml` into Synology Container Manager
- Replace `HANDY_MASTER_SECRET`
- `PUBLIC_URL` is optional; if you have a reverse proxy in front, you can leave it unset initially
- Deploy

## Notes

- Container startup runs:
  - `./happy-server migrate`
  - then `./happy-server serve`
- Storage defaults:
  - PGlite in `/data/pglite`
  - local files in `/data/files`
- Default port is `3005`
- This is designed so Synology only pulls an image; it does **not** build on NAS
