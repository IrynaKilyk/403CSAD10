#!/usr/bin/env bash
set -euo pipefail

mkdir -p build
cargo build --release
cargo test --release
cp target/release/hello build/hello
