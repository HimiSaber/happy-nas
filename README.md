# happy-nas

Minimal wrapper repository for building a Synology/NAS-friendly Happy Server image via GitHub Actions and publishing it to GHCR.

## What this repo does

- Builds an image for `linux/amd64` (x86 NAS / Synology)
- Clones the upstream `slopus/happy` repository during image build
- Packages `packages/happy-server` into a single GHCR image
- Uses the standalone server flow so NAS deployment does **not** need local Postgres / Redis / S3
- Provides a simple Synology-friendly `compose.yaml`

## Image

- `ghcr.io/himisaber/happy-server:latest`
- `ghcr.io/himisaber/happy-server:main`

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
- Replace `PUBLIC_URL`
- Deploy

## Notes

- The container starts with:
  - `yarn --cwd packages/happy-server standalone migrate`
  - then `yarn --cwd packages/happy-server standalone serve`
- Storage defaults:
  - PGlite in `/data/pglite`
  - local files in `/data/files`
- Default port is `3005`
- This is designed so Synology only pulls an image; it does **not** build on NAS
