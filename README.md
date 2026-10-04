# docker-xrpld

Container image for running an `xrpld` (XRP Ledger, formerly `rippled`) node,
built straight from the upstream XRPLF package repository — no third-party
image dependency.

## xrpld (XRP Ledger, formerly rippled)

Replacement for the community `xrpllabsofficial/xrpld` image (archived
2026-09-21, never published 3.4.x). Installs the signed `xrpld` package from
<https://packages.xrplf.org> on `ubuntu:noble`.

```sh
docker build --platform linux/amd64 -t pfc/xrpld:3.4.1 .
docker run --rm --platform linux/amd64 pfc/xrpld:3.4.1 xrpld --version
```

- `version` is the single source of truth and the image tag; the deb packaging
  revision is resolved from the repo at build time.
- The XRPLF repo signing key is vendored (`xrplf.asc`) and fingerprint-pinned
  in the Dockerfile.
- amd64 only (XRPLF publishes no arm64 debs) — pin `--platform linux/amd64`
  on Apple Silicon.
- No `ENTRYPOINT`/`CMD`: the consuming Helm chart drives the process
  (`command: [rippled, --conf=...]`). A `rippled -> xrpld` symlink and
  `/var/log/rippled` are provided for drop-in compatibility with charts
  written for the old image.

## CI

`.github/workflows/build-image.yml` publishes to GHCR on `v*` tags:

```sh
git tag v3.4.1 && git push origin v3.4.1
# -> ghcr.io/pfc-validator/docker-xrpld:3.4.1 (+ :latest)
```

The tag must match `./version` exactly or the build fails. Pushes to `main`
run a build-only validation without publishing.
