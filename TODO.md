# TODO — divergences from upstream Arch

Every deliberate difference between this port and Arch's own packages, so
that none of them becomes invisible. A port that does not track what it gave
up drifts silently, and the gap is discovered years later by whoever needs
the missing feature.

Two kinds of entry, and the difference matters:

- **Deferred** — dropped to get the bootstrap moving. Nothing about s390x
  prevents it; it costs build time, a host dependency, or another package
  first. These should come back.
- **Architectural** — the thing being dropped is x86-specific by nature.
  There is nothing to restore.

Each entry names the hook that implements it, so the change is one file away.

---

## Deferred

### libgccjit — `patches/pkgbuild/gcc.sh`

Arch configures and compiles the **entire gcc tree a second time** just for
libgccjit, because it needs `--enable-host-shared` and applying that to the
main compiler would slow it down. That pass is about half of gcc's build
time — twenty minutes per attempt on this hardware.

Already re-enablable, no code change needed:

    EL_GCC_JIT=1 bash scripts/build-stage1.sh

**To close:** run one build with the switch on and confirm the package
appears. Nothing else is required.

### HTTP/3 in curl — `patches/pkgbuild/curl.sh`

    configure: error: nghttp3 enabled without a QUIC library; enable ngtcp2

Ubuntu packages neither ngtcp2 nor nghttp3, so the build host cannot satisfy
them. pacman talks to plain HTTPS mirrors, and so does ERPLibre.

**To close:** build `ngtcp2` and `nghttp3` as Arch packages, add them to the
stage-1 list before curl, then delete the hook.

### gcc front ends: Ada, D, Modula-2, COBOL — `patches/pkgbuild/gcc.sh`

    configure: error: GNAT is required to build ada
    configure: error: GDC is required to build d

These are written in themselves and need an existing compiler of the same
language. Ubuntu ships `gnat`, but not a version GCC 15 accepts; there is no
D bootstrap compiler here at all.

**To close:** after stage 2, the port's own gcc can bootstrap them. This is
the entry most likely to matter to someone — a mainframe shop with Ada is not
a hypothetical.

### Test suites — `scripts/bootstrap-pacman.sh` (`--nocheck`)

Stage-1 suites run against the **host** libraries, not Arch's, so their
verdict says nothing about the port. `acl` failed its check step on a sound
build. They also cost hours.

**To close:** stage 2 runs inside the chroot, where the suites test what was
actually built. Drop `--nocheck` there.

### Checksums on generated patches — `scripts/bootstrap-pacman.sh`

`--skipchecksums`. GitLab regenerates `.patch` URLs, so their checksums drift
from what the PKGBUILD recorded. Release tarballs still validate — only the
generated patches are skipped.

**To close:** fetch patches from a stable source, or record our own sums.

### PGP signatures — `scripts/bootstrap-pacman.sh`

`--skippgpcheck`, because no keyring exists yet.

**To close:** build `archlinux-keyring`, then verify.

---

## Architectural

Nothing to restore here. Listed so nobody spends an afternoon rediscovering
why.

| What | Where | Why |
|---|---|---|
| SFrame | `glibc.sh` | `configure: error: the architecture doesn't support SFrame` |
| gold linker | `binutils.sh` | x86-centric, deprecated upstream since 2.44; `ld.bfd` is the linker on Z |
| 32-bit multilib | `glibc.sh`, `gcc.sh`, `libtool.sh` | On x86_64 it means i686. On Z it means the 31-bit ESA/390 ABI that GCC is removing |
| `libhwasan` | `gcc.sh` | Hardware-assisted ASan exists on x86_64 and aarch64 only |

---

## Environment, not the port

### libassuan source — `patches/pkgbuild/libassuan.sh`

`dev.gnupg.org` is unreachable from this build host — measured HTTP 000,
while `github.com/gpg/libassuan.git` and `gnupg.org/ftp` both answer. Only
the transport changed; the pinned tag is untouched.

**To close:** it closes itself on a host with wider outbound access.

### `arch-meson` / `arch-cmake` — `scripts/devtools/`

Several PKGBUILDs call them, they ship in `devtools`, and `devtools` is
itself an Arch package — during a bootstrap they cannot exist yet.

**To close:** build `devtools` in stage 2 and drop the stand-ins.

### Host include layout — `scripts/bootstrap-pacman.sh`

Ubuntu multiarch puts `asm/`, `bits/`, `gnu/` and `sys/sdt.h` under
`/usr/include/s390x-linux-gnu`, while glibc builds with `-nostdinc` and
expects the classic layout. Symlinks bridge it.

**To close:** stage 2 builds inside an Arch root, where the layout is
already right.
