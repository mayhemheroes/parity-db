#!/usr/bin/env bash
#
# parity-db/mayhem/build.sh — build parity-db's cargo-fuzz targets as sanitized
# libFuzzer binaries (OSS-Fuzz Rust path: cargo-fuzz + ASan via RUSTFLAGS), then
# pre-build the project's own test suite so mayhem/test.sh only RUNS it.
#
# The fuzz crate is the ADDITIVE mayhem/fuzz/ sub-workspace: upstream's fuzz/
# crate no longer compiles at tip (it requests a removed `arbitrary` cargo
# feature of parity-db), so mayhem/fuzz/ carries upstream's two model harnesses
# (simple_model, refcounted_model — copied verbatim, built against the
# `instrumentation` feature) plus the ported open_metadata harness (drives the
# same metadata-parsing path through the public Options::load_metadata_file).
#
# AIR-GAPPED CONTRACT (SPEC §6.5): the PATCH tier re-runs THIS script OFFLINE.
# This first (online) build populates the cargo registry under $CARGO_HOME
# (/opt/toolchains/rust/cargo, pinned by the Dockerfile ENV); the offline re-run
# resolves crates from that cache (the rlenv runtime exports CARGO_NET_OFFLINE=true).
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${MAYHEM_JOBS:=$(nproc)}"
# cargo-fuzz has no --jobs flag; cargo reads parallelism from CARGO_BUILD_JOBS.
export CARGO_BUILD_JOBS="$MAYHEM_JOBS"

cd "$SRC"

# Rust note: sanitizer instrumentation comes via RUSTFLAGS (-Zsanitizer=address, the
# OSS-Fuzz Rust path) — the base's clang $SANITIZER_FLAGS don't apply to rustc. Kept
# defaulted for parity with the C/C++ contract (cc-built dep crates may consume it).
SANITIZER_FLAGS="${SANITIZER_FLAGS=}"

# RUST_DEBUG_FLAGS threads DWARF < 4 symbols (§6.2 item 10): debuginfo for triage,
# -Z dwarf-version=3 for the rustc CUs, and the -Clinker cc-wrapper that prepends a
# DWARF3 anchor object so the FIRST .debug_info CU is v3 (the precompiled ASan
# runtime CUs are v5 and can't be lowered — see the Dockerfile).
: "${RUST_DEBUG_FLAGS:=-C debuginfo=2 -Z dwarf-version=3 -Clinker=/opt/mayhem-dwarf3-anchor/cc-wrapper.sh}"
export RUST_DEBUG_FLAGS

# OSS-Fuzz Rust libFuzzer+ASan flags. --cfg fuzzing matches libfuzzer-sys;
# force-frame-pointers aids ASan backtraces.
export RUSTFLAGS="${RUSTFLAGS:-} --cfg fuzzing $RUST_DEBUG_FLAGS -Zsanitizer=address -Cforce-frame-pointers"

FUZZ_DIR="mayhem/fuzz"
TRIPLE="x86_64-unknown-linux-gnu"

# Discover every target from the crate's fuzz_targets/ dir (one binary per target).
FUZZ_TARGETS=()
for f in "$FUZZ_DIR"/fuzz_targets/*.rs; do
  FUZZ_TARGETS+=("$(basename "${f%.*}")")
done
[ "${#FUZZ_TARGETS[@]}" -gt 0 ] || { echo "ERROR: no fuzz targets under $FUZZ_DIR/fuzz_targets/" >&2; exit 1; }

echo "=== cargo fuzz build (image nightly, ASan via RUSTFLAGS) ==="
echo "RUSTFLAGS=$RUSTFLAGS"
echo "targets: ${FUZZ_TARGETS[*]}"

# Use the image's DEFAULT toolchain (the Dockerfile pinned it). A `+toolchain`
# override would make rustup try to install another channel into /opt/toolchains/rust.
for t in "${FUZZ_TARGETS[@]}"; do
  echo "--- building fuzz target: $t ---"
  cargo fuzz build --fuzz-dir "$FUZZ_DIR" -O --debug-assertions "$t"
  bin="$SRC/$FUZZ_DIR/target/$TRIPLE/release/$t"
  [ -x "$bin" ] || { echo "ERROR: expected fuzz binary not found at $bin" >&2; exit 1; }
  cp "$bin" "/mayhem/$t"
  echo "built /mayhem/$t"
done

# Pre-build the project's OWN test suite (workspace: parity-db + admin) with the
# project's NORMAL flags — mayhem/test.sh only RUNS it (no compiling there).
echo "=== pre-building the upstream test suite (cargo test --no-run) ==="
RUSTFLAGS="" cargo test --workspace --no-run --jobs "$MAYHEM_JOBS"

echo "build.sh complete:"
ls -la /mayhem/simple_model /mayhem/refcounted_model /mayhem/open_metadata
