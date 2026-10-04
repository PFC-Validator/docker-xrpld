########################################################################################
# xrpld (XRP Ledger, formerly rippled)
#
# The community image this chart previously used (xrpllabsofficial/xrpld,
# WietseWind/docker-xrpld) was archived by its owner on 2026-09-21 and never
# published 3.4.0: with the 3.4.0 release XRPLF moved the DEB/RPM packages to
# packages.xrplf.org under an XRPLF signing key, which broke that image's build
# (docker-xrpld#31). We build our own instead, installing the signed xrpld
# package straight from packages.xrplf.org — no third-party image dependency.
#
# The binary was renamed rippled -> xrpld upstream (3.2.0). The chart still
# invokes `rippled` (command + probe/ready scripts), so we add a rippled -> xrpld
# symlink for drop-in compatibility; no chart command/script change is required.
########################################################################################

FROM ubuntu:noble

ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8

# ./version is the single source of truth (and the published image tag). The deb
# packaging revision (e.g. -1) is resolved from the repo at build time, so bumping
# the release only touches ./version.
COPY version /version

# XRPLF package signing key, VENDORED and fingerprint-PINNED (not fetched at build
# time) so the trust root is auditable and a compromised packages.xrplf.org cannot
# swap it. apt then verifies the repo's signed Release against this key, and the
# Release hashes chain down to the xrpld .deb — so the installed binary is
# authenticated and integrity-checked against this pinned key.
COPY xrplf.asc /tmp/xrplf.asc
# XRPLF Packages <distribution@xrplf.org>, rsa4096, created 2026-08-18. Fingerprint
# confirmed against the official install docs (XRPLF/xrpl-dev-portal#3951). NB this is
# the apt-repo key, NOT the "TechOps Team at Ripple" release-signing key (E057…FAA6)
# that signs the GitHub release binaries — a separate channel. Re-check on key rotation.
ARG XRPLF_SIGNING_FINGERPRINT=B655416741221F780FBCFBC9AA84D41A11D29FA9

RUN set -eu \
  && VERSION="$(sed 's/-.*//' </version)" \
  && apt-get update -y \
  && apt-get install --no-install-recommends -y ca-certificates=20* gnupg=2.4.* \
  # verify the vendored key: exactly one public key, with the expected fingerprint
  && gpg --batch --show-keys --with-colons /tmp/xrplf.asc > /tmp/keys.txt \
  && [ "$(grep -c '^pub:' /tmp/keys.txt)" = "1" ] \
  && grep -q "^fpr:::::::::${XRPLF_SIGNING_FINGERPRINT}:$" /tmp/keys.txt \
  && install -d -m 0755 /etc/apt/keyrings \
  && install -m 0644 /tmp/xrplf.asc /etc/apt/keyrings/xrplf.asc \
  && echo "deb [signed-by=/etc/apt/keyrings/xrplf.asc] https://packages.xrplf.org/repository/deb-stable any main" \
       > /etc/apt/sources.list.d/xrplf.list \
  && apt-get update -y \
  # resolve the exact deb (VERSION + its packaging revision) from the repo, so ./version
  # is the only thing to bump; fail loudly if the repo has no matching build
  && XRPLD_DEB="$(apt-cache madison xrpld | awk -v v="$VERSION" '$3 ~ ("^" v "(-|$)") {print $3; exit}')" \
  && { [ -n "$XRPLD_DEB" ] || { echo "no xrpld deb matching ${VERSION} in packages.xrplf.org"; exit 1; }; } \
  && apt-get install --no-install-recommends -y "xrpld=${XRPLD_DEB}" \
  # rippled -> xrpld drop-in for the chart's command + probe/ready scripts
  && ln -sf "$(command -v xrpld)" /usr/local/bin/rippled \
  # the chart's rippled.cfg logs to /var/log/rippled/debug.log; that path is NOT a
  # volume mount, so the image must own it (the old community image did).
  # /var/lib/rippled is the PVC mount point (k8s creates it), so it's not made here.
  && mkdir -p /var/log/rippled \
  # provenance/version assertion: build fails if the installed binary isn't $VERSION
  && rippled --version | grep -F "$VERSION" \
  # ca-certificates stays (xrpld fetches [validator_list_sites] over HTTPS); drop gnupg
  && apt-get purge -y gnupg \
  && apt-get autoremove -y \
  && rm -rf /var/lib/apt/lists/* /tmp/xrplf.asc /tmp/keys.txt

# The Helm chart drives the process (`command: [rippled, --conf=/scripts/rippled.cfg]`)
# and mounts its own config + scripts, so no ENTRYPOINT/CMD is set here.