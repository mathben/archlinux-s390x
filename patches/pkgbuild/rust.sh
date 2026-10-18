#!/usr/bin/env bash
# rust: an s390x target list, and an upstream stage0.
#
# Arch ships one bootstrap toml PER ARCHITECTURE -- x86_64, aarch64, loong64,
# riscv64 -- and prepare() reads bootstrap.${CARCH}.toml. There is no s390x
# file, so this hook writes one. The rest of the PKGBUILD already ports itself:
# build() ends its host_tuple case on
#
#   *) host_tuple=$CARCH-unknown-linux-gnu ;;
#
# which is right for s390x, and leaves do_pgo=0 for anything that is not x86_64
# or aarch64. The package_rust() case has no catch-all either, so the cross
# targets are skipped rather than half-applied.
#
# THE STAGE0. Rust is built by the previous rust, and this port has none. The
# host has Ubuntu 1.85.1 -- thirteen releases behind what 1.98.0 accepts. So the
# toml names NO rustc, cargo or rustfmt, and bootstrap.py fetches the official
# stage0 for its own triple, with the checksums in src/stage0. MEASURED, not
# assumed: rust-1.97.0- and rust-1.98.0-s390x-unknown-linux-gnu.tar.xz both
# answer 200.
#
# That is a binary this port did not build, and it should be said plainly. It is
# also how every distribution starts a rust chain: follow Arch own /usr/bin/rustc
# back far enough and it is an upstream tarball too.
#
# AND SO 0003-bootstrap-Workaround-for-system-stage0.patch GOES. It exists ONLY
# because Arch bootstraps from a system stage0 in /usr: it narrows a sysroot copy
# from lib to lib/rustlib so the whole of /usr/lib is not copied
# (rust-lang/rust#143735). With a downloaded stage0 in build/, there is nothing
# to protect against, and the unpatched copy is what upstream tests.
#
# WHAT IS DROPPED, deliberately:
#   - the musl and wasm32 targets, with the rust-musl and rust-wasm packages
#     that carry them. They need musl, wasi-libc and wasm-component-ld, none of
#     which this port builds. THE TWO _pick LINES GO WITH THEM -- _pick is an
#     mv, so a target that was never built is not an empty package but a failed
#     package(). That is the documentation pattern again, in a new costume:
#     disable the producer, and the consumer is still standing there.
#   - sanitizers and profiler, and so compiler-rt from depends(). Arch itself
#     sets sanitizers = false for every target that is not the build host; this
#     extends that to ours instead of spending an LLVM-sized build on runtimes
#     nothing in this port uses.
#
# lld STAYS in depends, and is not optional: package_rust() links
# usr/bin/{ld.lld,ld64.lld,lld-link,wasm-ld} into rustlib gcc-ld.
set -euo pipefail

cat > bootstrap.s390x.toml <<"ZZTOML"
# see src/bootstrap/src/utils/change_tracker.rs
change-id = 154587

[llvm]
download-ci-llvm = false
link-shared = true

[gcc]
download-ci-gcc = false

[build]
description = "%description%"
target = [
  "s390x-unknown-linux-gnu",
]
locked-deps = true
vendor = true
tools = [
  "cargo",
  "clippy",
  "rustdoc",
  "rustfmt",
  "rust-analyzer-proc-macro-srv",
  "analysis",
  "src",
]
sanitizers = false
profiler = false
docs = false

[install]
prefix = "/usr"

[rust]
codegen-units = 16
codegen-units-std = 1
debuginfo-level = 2
debuginfo-level-std = 2
channel = "stable"
rpath = false
frame-pointers = true
lld = false
bootstrap-override-lld = "external"
llvm-bitcode-linker = false
deny-warnings = false
backtrace-on-ice = true
remap-debuginfo = false
lto = "thin"
parallel-frontend-threads = 0

[dist]
compression-formats = ["gz"]
compression-profile = "fast"

[target.s390x-unknown-linux-gnu]
llvm-config = "/usr/bin/llvm-config"
optimized-compiler-builtins = false
ZZTOML

python3 - <<"ZZPY"
import io

s = io.open("PKGBUILD", encoding="utf-8").read()

# 1. makepkg reads source_${CARCH}; without this the toml is never staged.
old = "source_x86_64=(bootstrap.x86_64.toml)"
assert s.count(old) == 1, "rust: no source_x86_64 line"
s = s.replace(old, old + "\nsource_s390x=(bootstrap.s390x.toml)", 1)

# 1 bis. UNE SOURCE SANS SOMME ARRÊTE makepkg, MÊME LOCALE.
#
# L'amont donne un b2sums_<arch> pour chaque source_<arch>. En ajoutant
# source_s390x sans son pendant, les deux tableaux cessent d'avoir la même
# taille et makepkg refuse avant de bâtir :
#
#   ERROR: Integrity checks (b2) differ in size from the source array.
#
# Invisible tant que --skipchecksums était passé ; immédiat depuis que les
# sommes sont vérifiées. La somme est CALCULÉE et non SKIP : ce crochet est
# l'auteur du fichier, donc il peut en répondre, et le contrôle attrapera
# une sortie corrompue de sa propre main.
import hashlib
_b2 = hashlib.blake2b(io.open("bootstrap.s390x.toml", "rb").read()).hexdigest()
old = "b2sums_x86_64=("
hit = [k for k, l in enumerate(s.split("\n")) if l.startswith(old)]
assert len(hit) == 1, "rust: une seule ligne b2sums_x86_64 attendue"
lines = s.split("\n")
lines.insert(hit[0] + 1, "b2sums_s390x=('%s')" % _b2)
s = "\n".join(lines)

# 2. the system-stage0 workaround, which a downloaded stage0 does not want.
lines = s.split("\n")
hit = [i for i, l in enumerate(lines)
       if l.strip() == "0003-bootstrap-Workaround-for-system-stage0.patch"]
assert len(hit) == 1, "rust: expected one 0003 patch entry, got %d" % len(hit)
del lines[hit[0]]
s = "\n".join(lines)

# 3. only the two packages whose files this build actually produces.
old = """pkgname=(
  rust
  rust-musl
  rust-src
  rust-wasm

  # x86_64 only
  lib32-rust-libs

  # cross targets
  rust-aarch64-gnu
  rust-aarch64-musl
)"""
assert s.count(old) == 1, "rust: pkgname block not as expected"
s = s.replace(old, "pkgname=(\n  rust\n  rust-src\n)", 1)

# 4. the consumers of the targets removed in 3.
lines = s.split("\n")
keep = [l for l in lines
        if l.strip() not in ("_pick dest-musl usr/lib/rustlib/${host_tuple/gnu/musl}",
                             "_pick dest-wasm usr/lib/rustlib/wasm32{,v1}-*")]
assert len(lines) - len(keep) == 2, "rust: expected 2 _pick lines, removed %d" % (len(lines) - len(keep))
s = "\n".join(keep)

# 5. sanitizers and profiler are off, so the runtime that serves them is not a
#    dependency. depends= only -- makedepends is never consulted under --nodeps.
lines = s.split("\n")
dep0 = lines.index("depends=(")
dep1 = next(i for i in range(dep0, len(lines)) if lines[i] == ")")
hit = [i for i in range(dep0, dep1) if lines[i].strip() == "compiler-rt"]
assert len(hit) == 1, "rust: compiler-rt not found once in depends"
del lines[hit[0]]
s = "\n".join(lines)

io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY

grep -q "^source_s390x=(bootstrap.s390x.toml)$" PKGBUILD || { echo "rust: source_s390x missing" >&2; exit 1; }
grep -q "0003-bootstrap-Workaround" PKGBUILD && { echo "rust: the system-stage0 patch is still applied" >&2; exit 1; }
grep -qE "^\s+(rust-musl|rust-wasm|lib32-rust-libs)$" PKGBUILD && { echo "rust: a package with no targets is still listed" >&2; exit 1; }
grep -qE "^\s+_pick dest-(musl|wasm)" PKGBUILD && { echo "rust: a _pick without a target survived" >&2; exit 1; }
grep -qE "^\s+rustc = " bootstrap.s390x.toml && { echo "rust: the toml names a stage0 that does not exist" >&2; exit 1; }
echo "rust: s390x target list written, upstream stage0, musl/wasm/sanitizers dropped"
