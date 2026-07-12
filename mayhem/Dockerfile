# syntax=docker/dockerfile:1.7
#
# Commit-image Dockerfile — RUST target (cargo / cargo-fuzz). Builds ON TOP of the
# org C/C++ base (ghcr.io/mayhemheroes/base), adding a pinned Rust nightly +
# cargo-fuzz under /opt/toolchains/rust, then runs mayhem/build.sh + mayhem/test.sh.
#
# parity-db is a pure-Rust embedded key-value database. The fuzz targets live in
# the ADDITIVE mayhem/fuzz/ crate (upstream's fuzz/ crate no longer compiles at
# tip — it depends on a removed `arbitrary` cargo feature), and are built the
# OSS-Fuzz Rust way: cargo-fuzz + ASan via RUSTFLAGS.
#
# Build (from the repo root, on the `mayhem` branch):
#   DOCKER_BUILDKIT=1 docker build -f mayhem/Dockerfile \
#       --build-arg COMMIT=$(git rev-parse HEAD) \
#       [--build-arg SOURCE_DATE_EPOCH=$(date +%s)] -t parity-db-commit:test .

FROM ghcr.io/mayhemheroes/base:20260621

ARG COMMIT
ARG REPO_URL
# SOURCE_DATE_EPOCH stays an ARG (never an ENV — an empty ENV breaks clang). build.sh unsets it when empty.
ARG SOURCE_DATE_EPOCH
# Undefaulted (no '=') so the base ENV default flows through unless --build-arg overrides it.
ARG SANITIZER_FLAGS

# Pin the channel by DATE: -Zsanitizer=address (the OSS-Fuzz Rust ASan path) needs
# nightly, and a dated nightly keeps the build reproducible. Pin cargo-fuzz too.
ARG RUST_CHANNEL=nightly-2025-09-05
ARG CARGO_FUZZ_VERSION=0.12.0

# Rust toolchain @ a FIXED, lockable, $HOME-independent prefix (SPEC §6.2 item 8):
# the cargo registry this FIRST (online) build populates is found again — by the
# SAME absolute CARGO_HOME — when the PATCH RL tier re-runs build.sh offline.
ENV RUSTUP_HOME=/opt/toolchains/rust/rustup \
    CARGO_HOME=/opt/toolchains/rust/cargo \
    PATH=/opt/toolchains/rust/cargo/bin:${PATH}

USER root
RUN install -d /opt/toolchains/rust \
 && curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs -o /tmp/rustup-init.sh \
 && sh /tmp/rustup-init.sh -y --no-modify-path --profile minimal \
        --default-toolchain "${RUST_CHANNEL}" \
 && rustup component add rust-src --toolchain "${RUST_CHANNEL}" \
 && cargo install cargo-fuzz --version "${CARGO_FUZZ_VERSION}" --locked \
 && rm -f /tmp/rustup-init.sh \
 # The commit build AND the air-gapped PATCH re-run run as `mayhem` (2000): it must
 # read the toolchain and read/refresh the cargo registry cache, so hand the whole
 # prefix to 2000.
 && chown -R 2000:2000 /opt/toolchains/rust

# DWARF<4 gate workaround for Rust/cargo-fuzz (§6.2 item 10).
# cargo-fuzz links the Rust nightly ASan runtime archive (librustc-nightly_rt.asan.a)
# via --whole-archive, and that archive's objects (compiled with DWARF v5) land FIRST
# in .debug_info before any user/std CUs. `-Z dwarf-version=3` only controls rustc's
# own CUs. Fix: compile a tiny stub with clang -gdwarf-3 and inject it as the FIRST
# object in every link via a cc-wrapper (-Clinker=...), so the first CU is DWARF v3.
RUN set -eux; \
    mkdir -p /opt/mayhem-dwarf3-anchor; \
    printf 'void __mayhem_dwarf3_anchor(void) __attribute__((visibility("hidden"),used));\nvoid __mayhem_dwarf3_anchor(void) {}\n' \
      > /opt/mayhem-dwarf3-anchor/anchor.c; \
    clang -g -gdwarf-3 -c /opt/mayhem-dwarf3-anchor/anchor.c \
      -o /opt/mayhem-dwarf3-anchor/anchor.o; \
    printf '#!/bin/bash\nexec cc /opt/mayhem-dwarf3-anchor/anchor.o "$@"\n' \
      > /opt/mayhem-dwarf3-anchor/cc-wrapper.sh; \
    chmod +x /opt/mayhem-dwarf3-anchor/cc-wrapper.sh; \
    chmod a+rX /opt/mayhem-dwarf3-anchor /opt/mayhem-dwarf3-anchor/anchor.o \
               /opt/mayhem-dwarf3-anchor/cc-wrapper.sh

# Source enters from the build CONTEXT (CI checkout): the FULL repo (incl. .git) → /mayhem.
USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

# Populates $CARGO_HOME (online, this first build) and builds the sanitized fuzz target(s).
RUN bash mayhem/build.sh

# Run the project's functional suite at build time (a failing suite fails the build).
RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh — repo ships no functional tests"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
