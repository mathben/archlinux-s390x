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

### Host sonames the target does not have — `scripts/test-chroot.sh` check 3

Nine libraries are requested by a shipped binary at the HOST's version while
the repository ships the same library at Arch's:

| requested | by | we ship |
|---|---|---|
| `libgpgme.so.11` | pacman (via libalpm) | gpgme 2.x, `.45` |
| `libnettle.so.8`, `libhogweed.so.6` | gnutls, libcurl-gnutls | nettle |
| `libicuuc.so.76` | libxml2 | icu |
| `liblmdb.so.0` | krb5 | lmdb |
| `libnsl.so.2` | pam | libnsl |
| `libsasl2.so.2` | libldap, openldap | libsasl |
| `libsodium.so.23` | openldap | libsodium |
| `libdevmapper.so.1.02.1` | cryptsetup | device-mapper |

This is stage 1 working as designed, not a defect list: stage 1 links the
host, so it records the host's sonames. It is written down because the
consequence is concrete — `pacman` in the stage-1 rootfs does not start:

    pacman: error while loading shared libraries: libgpgme.so.11

**To close:** stage 2. Every one of these dissolves when the package is
rebuilt inside the chroot against the repository's own libraries. Nothing here
should be hooked in stage 1; a hook would only hide it.

Note for stage 2's design: because pacman cannot run inside the stage-1
rootfs, stage 2 has to install with the HOST's pacman and `--root`, the way
scripts/test-chroot.sh already does, and use the chroot only for building.

### Three sonames with no provider at all — same check

Distinct from the nine above, and each for its own reason:

- `libpython3.13.so.1.0` ← `util-linux-libs`. It ships
  `pylibmount.cpython-313-*.so`, built against the host's python. Inert: this
  port ships no python, so nothing imports it. Stage 2 drops it by
  construction — the chroot has no python either, so meson will not build it.
  Worth naming because `arch-meson` was fixed to put this file in the right
  PLACE (site-packages, not dist-packages) and the wrong ABI stayed invisible
  until the soname audit.
- `libselinux.so.1` ← `glibc`'s `makedb`. Deliberate, see above.
- `libtcl8.6.so` ← `sqlite-tcl`, `sqlite-analyzer`. We ship tcl **9.0**;
  sqlite's configure found the host's 8.6 tclConfig.sh. An honest admission:
  the measurement that chose to BUILD tcl rather than drop these
  sub-packages compared closure cost and never looked at the ABI. Stage 2
  fixes it — tcl 9.0 is in the repository — but the reasoning had a blind
  spot, and it was the same blind spot as the pylibmount one.

### `lvm2` — `patches/pkgbuild/lvm2.sh`

Only `device-mapper` is built. The `lvm2` half declares
`thin-provisioning-tools`, which is Rust now, so a language runtime arrived
through a fourth-order dependency. Nothing in the repository wants `lvm2`
itself; cryptsetup wants device-mapper, which the same source produces.

**To close:** build Rust, restore the sub-package, rebuild. A target that
wants LVM needs this; dm-crypt and systemd do not.

### SQL auxprop in libsasl — `patches/pkgbuild/libsasl.sh`

Disabled. Its two database headers exist on this host, on paths configure does
not try (`/usr/include/postgresql`, `/usr/include/mariadb`). Arch declares
`depends=(glibc)` for libsasl because the plugins are dlopened, so nothing is
lost.

**To close:** supply the include paths, or leave it — a bootstrap has no SQL
authentication backend to serve.

### fuse2fs — `patches/pkgbuild/e2fsprogs.sh`

Not built: no fuse3 on the host, and none in the closure.

**To close:** add `fuse3`, and both the sub-package and the removal that feeds
it come back on their own.

### kbd without xkb — `patches/pkgbuild/kbd.sh`

`loadkeys` cannot generate keymaps from an XKB database. Arch's kbd cannot
either — it declares libxkbcommon nowhere, so Arch's chroot fails the same
probe. Building it would want libxcb and xkeyboard-config behind it.

**To close:** it is already closed with respect to Arch. Reopen only if a
target grows a graphics stack.

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

### Documentation is skipped in the stage-2 chroot — `scripts/build-stage2.sh`

Our own meson package ships `/usr/bin/arch-meson`, and it passes
`--auto-features enabled`. That is right on Arch, whose build chroot has every
optional tool installed. Ours has none of them:

    doxygen  xsltproc  asciidoctor  itstool  convert
    fig2dev  elinks    ducktype     yelp-build

With `enabled`, each absent tool is a hard error rather than a skipped
feature. libxml2 stopped on

    libxml2/doc/meson.build:3:10: ERROR: Program 'doxygen' not found

The chroot now gets a `/usr/local/bin/arch-meson` wrapper appending
`--auto-features auto` — meson honours the last occurrence, so every other
choice arch-meson makes survives. `/usr/local/bin` comes first on the
chroot's PATH; `/usr/bin/arch-meson` is left exactly as the package shipped it.

**Measured before choosing**, because building the tools was the alternative
and it is not close: doxygen alone wants `clang`, `fmt`, `spdlog` and
`llvm-libs` — a compiler infrastructure for a documentation generator. Behind
the other eight stand Ruby, ImageMagick and a GNOME stack. Several times the
size of everything built so far, for man pages.

To restore at stage 3, once there is somewhere to build them from.

### The docs split assumed the docs exist — `patches/pkgbuild/libxml2.sh`

Consequence of the above, and the **fourth** appearance of one shape: pam's
PDFs, e2fsprogs' `fuse2fs`, cmake's emacs byte-compilation, and now

    mv: cannot stat '<pkgdir>/usr/share/doc': No such file or directory

A failure on the last line of `package()`, after a completely successful
compile, naming a path instead of a reason. It has never once been a broken
build. The move is made conditional rather than deleted — on the host the docs
do exist and belong in their own package.

### libarchive drops xar for stage 1 — `patches/pkgbuild/libarchive.sh`

Stage 2 reached its first packaging step and stopped on

    bsdtar: error while loading shared libraries: libicuuc.so.76
    ==> ERROR: Failed to create package file.

The chain: `bsdtar` → `libarchive.so.13` → `libxml2.so.16` → `libicuuc.so.76`.
The libxml2 in the chroot is our stage-1 build, and stage 1 builds against the
HOST, whose ICU is 76; our icu package ships 78. So bsdtar cannot start — and
bsdtar is what makepkg uses to write the package. **The package that would fix
it is the one being built.** Nothing comes out of the chroot until this is
broken from outside it.

Supplying `libicuuc.so.76` from the host is the obvious move and the wrong
one: untracked host binaries in `/usr/lib` are exactly what test-chroot.sh's
ARTEFACT check exists to catch. A symlink to 78 does not work either — ICU
version-suffixes every symbol, so `libicuuc.so.78` does not define
`u_strlen_76`.

The root is that libarchive links libxml2 at all: it wants it for **xar**, an
Apple installer container. Nothing here reads one — makepkg writes
`.pkg.tar.gz`, pacman reads it. `--without-xml2 --without-expat` removes the
whole ICU chain instead of arguing about its version. Stage 1 only;
`STAGE2_SKIP_HOOKS` lists libarchive, so stage 2 builds it as Arch does,
against our own libxml2 and icu, where the versions agree.

### Rebuilding one package at stage 1 — `scripts/build-stage1.sh`

`build-stage1.sh` now takes package names, like stage 2 already did. Without
it, rebuilding one package meant deleting its line from `stage1.state` first —
editing the record of what was built in order to build something. That file is
this port's memory, and the standing instruction is to regenerate it from what
is really in `repo/s390x`, never from a log; hand-editing it is the same
mistake in a smaller form. An explicit name outranks the state file, because
being told "already built, skipping" would make the command useless for the
one job it has.

### 84 host binaries the chroot does not have — measured, not guessed

`install_host_deps` installs 110 apt packages. Asking dpkg what each ships in
`/usr/bin`, then testing every one of those against the stage-2 chroot, gives
84 absent binaries. Worth doing once rather than discovering them a package at
a time over a twenty-hour pass — two were found that way first (`rsync`,
`makeinfo`) and each cost a full build to surface.

Build tools, which will each block something:

    gperf  help2man  po4a  xsltproc  scdoc  dtrace (systemtap)
    cython  pyproject-build  sphinx-build  rst2man (docutils)

Documentation only, and settled by `--auto-features auto`:

    doxygen  asciidoctor  itstool  ducktype  yelp-build  yelp-check
    elinks  fig2dev  transfig  rsvg-convert  clang (doxygen's)

Not gaps at all, on inspection: `bison.yacc`, `fakeroot-tcp`, `faked-sysv`,
`automake-1.17`, `aclocal-1.17`, `ncurses6-config`, `nspr-config`,
`tcltk-depends` are Debian's alternative or versioned names for tools that are
present under Arch's names. Counting them as missing would have sent someone
building packages that already exist.

Each is built when a package actually asks for it, not in advance — several
carry closures much larger than themselves (`dtrace` brings systemtap,
`sphinx-build` a Python stack), and paying for one before knowing it is needed
is how a bootstrap doubles in size.

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
