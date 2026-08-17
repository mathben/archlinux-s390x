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

### PDF manuals in pam — `patches/pkgbuild/pam.sh`

Arch lists `fop` in makedepends, a Java renderer, to produce three PDFs that
the very next line of `package()` deletes as unreproducible. A JVM on the
build host buys nothing, so without it meson drops the PDF targets silently
and the `rm` is handed an unexpanded glob. The hook makes it `rm -f`.

**To close:** nothing needs closing. Listed because the hook's `-f` would
otherwise look like it is papering over a real absence.

### `libalpm.so` has no version — `/etc/makepkg.conf`

Every package in the repository declares bare sonames — `provides =
libalpm.so`, not `libalpm.so=16-64` — because `OPTIONS` carries `!autodeps`,
which is makepkg's own default. The soname scan never runs for any package.
Verified across all seventy.

Harmless today: our `depends` are equally unversioned, so the repository is
internally consistent and pacman resolves it. It breaks the moment anything
wants a versioned soname, as Arch's own packages do.

**To close:** enable `autodeps` and rebuild, or accept the divergence
knowingly. Not urgent, but it is a real difference from Arch's repository.

### `makedb` still links libselinux — no hook, deliberately

`glibc`'s `usr/bin/makedb` is the last binary in the repository carrying a
host artefact. It is the only one left of the six the audit found.

It is NOT hooked on purpose: nothing in the bootstrap runs `makedb`, and
rebuilding glibc for it would relink the foundation under every other
package.

**To close:** stage 2 rebuilds glibc in a chroot that has no libselinux, and
it closes itself.

### The python module brotli builds is unusable on the target — `patches/pkgbuild/brotli.sh`

The wheel is built by the host's python 3.13 and is ABI-tagged
`cpython-313`; Arch ships 3.14. No destination makes it importable. The hook
only moves it out of `/usr/local`, which an Arch package may not ship.

**To close:** stage 2 builds it with the port's own python.

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
| systemd-boot | `systemd.sh` | `meson.build:1627` maps a cpu family to an EFI machine type and s390x is not in the table. Z boots from an IPL record; there is no ESP to write into. `bootctl` is still built |

---

## The host decides what gets built

A category the first three did not cover, and the one that cost this round
the most. These are not choices anyone made. A build option's DEFAULT is
computed from the build machine, so installing an unrelated Ubuntu package
changes what a PKGBUILD produces — usually without failing, sometimes weeks
later.

Four were found, all in one round, all now pinned:

| Option | Where | What the host decides |
|---|---|---|
| `libdir` | `scripts/devtools/arch-meson` | meson asks `dpkg-architecture` and answers `lib/s390x-linux-gnu`. Five packages shipped their libraries where Arch's `ld.so` never looks |
| `python.platlibdir` | `scripts/devtools/arch-meson` | meson's python module uses Debian's `deb_system` scheme, `/usr/lib/python3/dist-packages` |
| `EXPAT_BUILD_DOCS` | `expat.sh` | ON if any of four docbook converters is on `PATH`. `asciidoc` pulled in `docbook-utils` as an automatic dependency, and expat — which had built clean the day before — started failing 29 hours later |
| `split-bin` | `systemd.sh` | probes whether the BUILD machine's `/usr/sbin` is a symlink. Ubuntu's is a real directory, so six binaries went to `/usr/sbin` and `package()` could not find them |

The general lesson: `arch-meson` passes `--auto-features enabled`, which
promotes every `auto` feature to a hard requirement. Installing a tool
therefore switches on code that has never compiled in this port. `util-linux`
was the clearest case — `asciidoctor` was needed for its man3 pages, and its
arrival enabled a translation step that had never once run.

**To close:** stage 2 builds inside an Arch root, where every one of these
defaults is already the right one. Until then, pin rather than hope.

---

## Environment, not the port

### Build locale — `scripts/bootstrap-pacman.sh`

`LC_ALL=C.UTF-8` on the `makepkg` line. This host runs `fr_FR.UTF-8`, and
util-linux's `poman-translate.sh` greps po4a's output for the English word
`Discard`. In French po4a says `Rejet de …`, so the skip list came out empty
and the build was handed 852 files po4a had never written.

`C.UTF-8` and not `C`: the Arabic and Ukrainian pages must stay valid UTF-8.
Arch's build chroot runs in this locale, so this is parity, not a workaround.

### `history.pc` — `scripts/bootstrap-pacman.sh`

GNU readline installs both `readline.pc` and `history.pc`; Debian and Ubuntu
keep the first and drop the second, while `libhistory.so` ships in
`libreadline-dev` regardless. libxml2 asks pkg-config for `history` and stops.

Our own readline package ships a correct `history.pc` — and copying it would
be wrong. Its `libdir` names `/usr/lib`, which on a multiarch host holds no
`libhistory`. The file has to describe the BUILD host, so it is generated.

### gnupg's feature set moved on its own — no hook

`libtss2-dev` was installed for systemd. gnupg's configure found it, turned
`TPM: no` into `TPM: yes`, and shipped `usr/lib/gnupg/tpm2daemon` — code that
had never compiled here. It built cleanly, and Arch's gnupg depends on
`tpm2-tss` too, so this is parity rather than drift.

Recorded because nobody decided it. It is the same mechanism as the table
above, caught on the way past.

**To close:** nothing. Noted so the next unexplained gnupg change has a
precedent to read.

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
