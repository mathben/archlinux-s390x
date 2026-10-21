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

    # Name gcc. Without an argument the pass walks the whole list, finds gcc
    # in the state file, prints "gcc already built, skipping", and the switch
    # is never read. An explicit request outranks the state file.
    EL_GCC_JIT=1 bash scripts/build-stage1.sh gcc

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

### The baseline CPU is z13 — decided, not inherited

`makepkg.conf` in the stage-2 chroot and `--with-arch` in `patches/pkgbuild/gcc.sh`.

zlib stopped on

    contrib/crc32vx/crc32_vx.c:205:10: error:
      '__builtin_s390_vec_unpackl' requires '-mvx'

*after* its own configure had detected vector support and defined
`-DHAVE_S390X_VX`. Both halves were right, which is what made it worth
measuring rather than patching:

| | `--with-arch` | default `-march` |
|---|---|---|
| host gcc (Ubuntu) | `z13`, tune `z16` | `arch11` = z13, 2015 |
| our gcc | *nothing* | `arch5` = z900, **2000** |

Arch's PKGBUILD names no s390x baseline because Arch has no s390x, so GCC fell
back to the oldest machine the target could possibly be. Every distribution
picks one of these. **This port had never said which, and silence chose the year
2000.**

z13 because that is what Ubuntu s390x — the host distribution — already
requires: adopting it cannot stop anything from running that runs today.

**Two places, two different questions.** `makepkg.conf` says how this
distribution is *compiled*. gcc's `--with-arch` says what the compiler we
*ship* assumes when someone builds on the target with no flags at all. Setting
only the first leaves a gcc that quietly reverts to arch5.

### The kernel — `patches/pkgbuild/linux.sh`

Arch builds one kernel package for one architecture, and every assumption that
follows from that is in this hook.

**The config is generated, not committed.** prepare() copies `config.$CARCH`,
Arch ships only `config.x86_64`, and a five-thousand-line file nobody here
could review would be worse than none. So the hook runs `make defconfig` over
`arch/s390/configs/defconfig`, enables the seventeen symbols a systemd guest
needs on top, and then ASSERTS each one against the FINAL `.config`. The
assertion is not decoration: `CONFIG_VIRTIO_CCW` does not exist, and
`drivers/s390/virtio/Makefile` builds virtio_ccw.o under `CONFIG_S390_GUEST`.
An `--enable` for a symbol Kconfig never heard of is a silent no-op, and the
price of not checking is one whole boot.

**`karch` is a directory name, and the map has one entry.**
package_linux-headers() translates CARCH into the `arch/` subdirectory it
copies and knows only `x86_64 -> x86`; s390x reaches `Unknown CARCH s390x`
AFTER the kernel has finished building. Same per-architecture hook as
`config.$CARCH` and rust's bootstrap toml, third appearance.

**The `initramfs` dependency goes.** It is a virtual package, provided by
mkinitcpio or dracut, and this port builds neither -- nor needs one: ext4,
virtio-blk and the CCW transport are built in, which is exactly what the
assertions above guarantee. Left in place it is unsatisfiable, and pacman
refuses the entire transaction rather than the one dependency.

**BINFMT_MISC is enabled although nothing here executes a foreign format.**
systemd mounts proc-sys-fs-binfmt_misc and reports the system `degraded` when
it cannot. A failed unit should mean something the day a real one appears.

**htmldocs and the BTF header go, with their consumers** -- `linux-docs` leaves
pkgname, `vmlinux.h` leaves linux-headers. Deferred like the rest of the
documentation: Sphinx is the tree this port has refused since llvm.

### cloud-init, and what a closure cannot see — `scripts/packages.sh`

Thirty packages. Twenty-two were computed: the PKGBUILDs were read by bash and
their `depends` followed until a pass added nothing, four passes deep. The
other eight appeared one at a time, from builds that failed, and every one of
them was a BUILD dependency -- a closure over `depends` cannot see those, and a
closure over `makedepends` drags in Sphinx, TeX Live and Qt, which is why it is
not the answer either.

What they taught is how an absence announces itself, which is rarely by name:

    Missing dependencies: calver          trove-classifiers, plainly
    Unknown version source: vcs           hatch-vcs, as a plugin error
    Cannot import 'maturin'               a build backend, not a library
    could not read Username for gitlab    the repository does not exist
    Dependency "bash-completion" not found  meson, at configure time

The git one cost the most: Arch packages python-yaml and PROVIDES
python-pyyaml, so asking for the provided name gets a password prompt rather
than a 404 — and, because nothing was ever read about python-yaml itself,
libyaml went missing too, one layer further down.

**The units matter as much as the package.** Arch ships cloud-init's four
units disabled. An image with the package and without them reads no seed at
all, and a deployment that applied nothing looks exactly like a deployment that
was ignored. `build-image.sh` takes `EL_CLOUD_INIT=1` and enables all four.

### Two images, and only one of them is generic — `scripts/build-erplibre-image.sh`

`build-image.sh` makes an Arch s390x that boots and can be logged into: the
COMMUNITY image, which a deployment then names, keys and hands an address. The
other one is ERPLibre already installed -- CPython 3.12.10 compiled by pyenv,
the wheels built, the database initialised, odoo a systemd unit -- and it is
made by driving the first: boot it, run provision-erplibre.sh over ssh, shut it
down.

**A booted guest, not a chroot.** provision-erplibre.sh starts units and reads
back /web/login over HTTP. A chroot has no PID 1 and shares the host's network,
so what it proves is not what a deployed machine does.

**AND THE IDENTITY COMES BACK OUT.** Everything installed is meant to be
identical on every copy; what identifies a MACHINE is not. ssh host keys leave,
so every deployment does not present the same fingerprint; machine-id is
emptied rather than deleted, which is how systemd is told to mint a new one at
first boot -- the journal and the DHCP client identifier both derive from it.
The build key leaves too: whoever deploys the image brings their own.

The database, the Python environment and the cloned sources STAY. They are the
product, and regenerating them is the hour this script spends once.

**Watching a remote job from outside is where this bites.** Asking the guest
whether the provisioning script still runs, by looking for its name in /proc,
answers yes forever: the ssh command carrying the question has that name in its
own command line and matches itself. The script's exit status is appended to
its log instead. That mistake was made five times in one session before it was
written down.

### The image was built by hand — `scripts/build-image.sh`

An image nobody can rebuild is an image that exists once. The first one was a
mkfs, a mount, a `pacman --root` and a dozen edits under /etc typed one at a
time; the script is that sequence, with the fifty-one packages read back out of
the running image with `pacman -Qqe` rather than remembered.

Three things it refuses to invent: a root password, a public key, and a
repository address. Each comes from the environment or the image ships without
it -- an image carrying a password somebody else chose is worse than one with
none, and it would be committed the day the script is.

**What DHCP does not bring.** networkd learns the nameserver and writes it
where resolved reads it, and nothing writes /etc/resolv.conf. Without that
symlink the guest has addresses and no names: `Could not resolve host` on the
first git clone, on a machine whose network is otherwise working.

**To close:** nothing here, but the image still boots a kernel handed to it
from outside -- see the entry above.

### A guest with no repository — `scripts/serve-repo.sh`

No Arch mirror publishes s390x, so a guest installed from this port boots with
an EMPTY mirrorlist. pacman runs and can do nothing: `no servers configured for
repository`, for every install, every upgrade, every dependency. It is not a
broken pacman, it is a machine with nowhere to look, and an Arch machine that
cannot install a package is not administrable.

The repository is served over HTTP from the host that built it, bound to the
libvirt NAT bridge, which its own guests and nothing else can reach.
`scripts/setup-guest-pacman.sh` is the other half, run inside the guest.

**STAGE 2 ONLY, AND NEVER STAGE 1.** Stage-1 packages were compiled against
Ubuntu's libraries -- dissolving that is the entire purpose of stage 2. Serving
them to a target would put the contamination back one package at a time. A
package the guest needs and stage 2 does not have is a package to BUILD.

~~**`SigLevel = Never` on that repository.**~~ **It is signed** --
`scripts/sign-repo.sh`. Not with archlinux-keyring, which would be an apparatus
of verification over packages Arch's developers never signed, but with a key
this port generates and keeps: 277 detached signatures, the database signed
too, and the public key served beside the packages.
`setup-guest-pacman.sh --verify` takes it into pacman's own keyring, signs it
LOCALLY -- pacman trusts a key the local keyring has signed, not one that is
merely present -- and raises SigLevel to `Required DatabaseRequired`.
`build-image.sh` does the same with `EL_VERIFY_REPO=1`.

Proven by taking a signature away: with the `.sig` moved aside, `pacman -S`
stops on a 404 and installs nothing; put back, the same command installs.

**What the key proves, and what it does not.** It has no passphrase -- two
hundred and seventy-seven signatures cannot each wait for a human, and a build
interrupted mid-signing leaves a repository in two states. So it proves a
package was built on this host and reached the guest unaltered. It does not
prove that nobody with an account on that host made it. The private key lives
under the work directory and never in git, where a signing key would be a
published key.

**A message that lied.** After SigLevel is raised, the database already in
/var/lib/pacman/sync was fetched when it was still Never, so it has no
signature beside it. pacman refuses it, re-downloads it, and succeeds -- having
printed `error: core: missing required signature` about a configuration that
was correct. The stale database is now removed before the sync, because an
error that appears when everything works teaches the reader to ignore errors.

### sudo and base-devel — the deployment's needs are not the chroot's

`packages.sh` refuses sudo for the build chroot and is right to: makepkg wants
it only for `--syncdeps`, which `--nodeps` replaces, so it would be a setuid
binary for no reason. That reasoning ends at the target. Every Arch guide, and
ERPLibre's own installer, is written as `sudo pacman -S --needed`; a machine
administrable only by logging in as root is not a deployment. Same argument
that admitted openssh.

`base-devel` stopped being a group in 2023 and is a meta package now, which is
why `pacman -Sg base-devel` reports that no such group exists. It compiles
nothing and names what a build machine needs. Two of its dependencies are not
here, and they are different kinds of absence:

- **debugedit is built** -- `patches/pkgbuild/debugedit.sh`. Its configure
  ABORTS without gdb-add-index, a tool that belongs to find-debuginfo and not
  to debugedit itself; gdb would drag in guile and source-highlight, and
  source-highlight boost. The abort becomes a warning. What is lost is exact:
  debug packages carry no gdb index.
- **archlinux-keyring is removed** -- `patches/pkgbuild/base-devel.sh`. It
  ships the PGP keys of Arch's developers, and not one package on this system
  was signed by them. Installing it would put a verification apparatus on a
  system where nothing is verified, which is worse than the gap it hides.

### What ERPLibre's Arch installer assumed — measured in a guest

`script/install/install_arch_linux.sh` stopped the whole installation on
`error: target not found: tk`, because tk sat on a critical pacman line and
pacman refuses an entire transaction over one unknown name. The same shape
waited two blocks below, where a missing nodejs `exit 1`s although everything
the script then does with node is already optional in its own error paths.

Both were argued from ERPLibre's own tree rather than from this port's
convenience: tk has two importers, one wrapping it in `try:` and one assuming a
browser and a screen; rtlcss builds right-to-left stylesheets and less compiles
LESS, which Odoo 18 replaced with libsass in Python. Neither is a server
dependency, and building tk here would mean tcl and a dozen X11 packages so
that a headless machine can open a file dialog.

**Closed ERPLibre-side**, not here: both moved to the best-effort loop the
script already had. The installer now reaches
`Arch Linux dependency installation done` on s390x.

### The first PKGBUILD this port writes itself — `pkgbuild/s390-tools/`

Every other package is Arch's, fetched and patched, and that is what keeps the
port a set of differences rather than a fork. It cannot cover a tool Arch has
no reason to package: zipl exists only on this architecture, so there is
nothing to clone and nothing to diff against. `build-stage2.sh` copies a
PKGBUILD from `pkgbuild/<name>/` when one is there, and copying is deliberately
NOT a fallback for a failed clone -- a network error would then quietly build
something other than what the name says.

Only zipl is built out of s390-tools' forty-odd tools. The rest drive DASD
volumes, zFCP adapters, crypto cards and HMC consoles: hardware a guest does
not have.

**Two things it taught, both about paths.** The Makefiles create the directory
of every tool whether it was built or not, and one of those is `/usr/lib64` --
a SYMLINK here, provided by filesystem, so pacman refuses the package outright.
And zipl reading its config asks the kernel for the geometry of the device
under /boot, which a loop device does not answer: at build time it is invoked
with `--target*` instead, declaring the geometry rather than asking for it.

### ~~The guest boots a kernel that is not in its filesystem~~ — it IPLs now

The domain carried `<kernel>`, a file on the host, because a z guest boots from
a record zipl writes and zipl was not built. `pacman -Syu linux` in the guest
then changed what the IMAGE held and not what the next boot RAN; a libvirt hook
papered over it by re-reading the kernel at every start.

zipl is built, `build-image.sh` writes the boot record, and the domain has no
`<kernel>` at all -- the hook is removed rather than left running over a file
nothing reads. Verified from a console that shows the guest's own loader:

    Using virtio-blk.
    Kernel command line: root=/dev/vda rw console=ttysclp0

That command line comes from the image's zipl.conf, which is how one can tell
the disk booted itself. A redefinition keeps the domain's uuid and MAC, so
re-running the installer no longer moves the guest to another address.

### libvirt-qemu needs one ACL to reach the image — `scripts/install-libvirt-domain.sh`

qemu runs as libvirt-qemu, and a home directory is 0750, so a domain cannot
open an image that lives in a work tree -- it cannot even traverse the
directory. `setfacl -m u:libvirt-qemu:x` on that one directory grants traversal
and not read, which is the smallest thing that works. The alternative is moving
a 24 GB image under /var/lib/libvirt, a tree that belongs to other work on the
host.

**To close:** nothing, unless the image acquires a home of its own.

### Stage 3, and the closure stage 2 never had — `STAGE_N`

Stage 3 is stage 2 pointed at itself: the chroot is populated from `repo2`
alone, the result lands in `repo3`, and the port is self-hosting when the two
agree. It needs no second script -- `STAGE_N=3` moves every path, and the four
hooks that read `EL_STAGE` only ask whether it is 1.

**The chroot compiles.** Eleven of eleven, gcc 16.2.1 and binutils 2.47 with
not one binary that was ever linked against Ubuntu. That is half of what
self-hosting means.

**What it found in the first minutes**, which is what a third stage is for:

- **Seven Python packaging tools were inherited, not declared.** setuptools is
  built with setuptools; at stage 2 it was there because stage 1 had left it
  and the restore put it back. A chroot made only of stage 2 starts without it
  and says `Cannot import 'setuptools.build_meta'`. They are named in
  CHROOT_PKGS now, like rsync before them.
- **The logs were named `stage2-log-*` whatever the stage**, so stage 3
  overwrote the very evidence a comparison would need. Ten paths, plus a FAIL
  message that pointed at an eleventh file that no longer existed.
- ~~**repo2 IS NOT CLOSED.**~~ **It is now**: 278 packages install together
  into an empty chroot, no fallback, and the chroot builds. Six holes, not
  five -- closing one opened another:

      pahole               <- linux-headers   built
      python-lark-parser   <- poetry-core     built
      python-pygments      <- cython          built, minus sphinx
      compiler-rt          <- clang           built, minus a bad assumption
      python-numpy         <- cython          dropped: cblas and lapack behind it
      python-matplotlib    <- ostra-cg        the sub-package goes instead

  Four of the six were missing for want of looking: pahole needs libelf and
  zlib, lark needs typing_extensions, pygments needs nothing. Only numpy and
  matplotlib were refused, both for the tree behind them, and in each case the
  cheaper half was kept -- pygments is built although numpy is not, and pahole
  is built although ostra-cg is not.

  **compiler-rt was not a missing package but a wrong assumption.** llvm-libc
  decides a platform has 128-bit complex if EITHER `__STDC_IEC_60559_COMPLEX__`
  or `__SIZEOF_FLOAT128__` is defined. On s390x the first is true and the
  second is not: the arithmetic exists, reached through `long double`, while
  `__float128` is an x86 spelling. The typedef then asks for a type nothing
  declares. Requiring the second alone lets the file's own third branch --
  `LDBL_MANT_DIG == 113` -> complex long double -- describe this architecture
  correctly. Upstream's condition is wrong for every machine like it.

  This was failure shape two, the one `--nodeps` makes possible. Stage 1 has a
  RESOLVE test for it and stage 2 never got one, so six holes sat there until a
  third stage tried to populate a chroot from stage 2 alone.

**Closed by a check, not by vigilance.** `resolve_check()` runs at the end of
every stage-2 pass: it asks pacman's own resolver whether everything in the
repository installs together, which is the question `--nodeps` stops anyone
from asking during the build. On its FIRST run it found a seventh hole nobody
had seen -- `git-zsh-completion` depends on zsh, which this port does not
build. Populating a chroot had never shown it, because pacman skips that
package as an alternative; the resolver, asked directly, named it in one
second.

The sub-package goes, like ostra-cg before it: a completion file for a shell
nobody can run is a dependency without a use. Verified after: `280 packages
resolve`.

Two things worth keeping from this. A check placed where the work happens
reports in seconds what a check somebody must remember to run reported one
stage late. And **closing a hole can open one** -- pahole brought ostra-cg,
which brought matplotlib -- so the check runs AFTER the pass, on what was just
built, not on what was expected.

### What stage 3 answered: 263 identical, 13 explained

228 of 231 packages rebuilt by the port's own toolchain, in a chroot holding
nothing that Ubuntu ever compiled. `compare-stages.sh` then read the two
repositories side by side: **263 packages identical**, thirteen different, and
not one of the thirteen is a contamination or a regression. They fall into
three groups.

**Stage 3 produces MORE, because its chroot holds more.** glibc gains its info
pages, util-linux its 124 bash completions, dbus its HTML documentation and man
pages, debuginfod its binary. Stage 2 built these inside a chroot populated
from stage 1 -- a deliberately narrow set -- and the missing tools made each
package quietly configure a smaller version of itself. Stage 3 populates from
the WHOLE of repo2, so texinfo, bash-completion and the rest are simply there.
bash-completion in particular was built today for cloud-init and reaches
util-linux by accident of being present.

That is not a defect to fix. It is the measurement saying that a package's
content depends on what surrounded its build, which is the thing a bootstrap
spends its life trying to control.

**Two versions carry a build date.** setuptools is `80.9.0.post20260821` on one
side and a later date on the other; meson the same. A package whose version
embeds the day it was built cannot be identical across two days, and nothing
can be done about it from here.

**cython declares numpy on one side.** Stage 3 built it before the hook that
removes that dependency existed. It will agree on the next pass -- a stale
artefact, not a difference between the stages.

**What this does and does not establish.** The toolchain reproduces itself:
glibc and gcc are among the 263. What is not yet established is a stage 3 built
in the same conditions as stage 2, which is what would make the comparison
answer a sharper question. Closing that means populating both chroots
identically -- and the honest way to do it is to give stage 2 the richer chroot,
not to impoverish stage 3.

**Three packages were never rebuilt**: rust (its build tree reached 19 GB and
filled the disk), libaio (its source is gone -- see the shape above), and
autoconf-archive (a GNU mirror answering 502 that afternoon).

### 18% of stage 1 is not pinned

`upstream-lock.sh verify` has always counted them, in a line nobody read:

    186 locked, 0 moved, 42 absent, 44 unlocked

Forty-four of the 235 stage-1 entries have no commit in upstream.lock, so a
fresh checkout clones whatever Arch publishes that day. Eight of them carry
a hook that asserts exact strings against that moving target -- compiler-rt
already fails against today's upstream, which is how the shape was found.

Not pinning them is deliberate and reasoned: a package on the list that has
never been built has no commit to record, and `write` covers it once it has.
The gap is that nothing says how large the unpinned share has grown. It does
now, as a percentage rather than a count.

**To close:** build the 42 absent checkouts once, then `upstream-lock.sh
write`. The two that cannot be locked that way are the recipes this
repository writes itself, which have no upstream to pin.

### A fifth failure shape: the source itself goes away

The three original shapes are about a package's dependencies, the fourth about
what a failed run leaves behind. This one is about the SOURCE, and stage 3 is
where it appears, because stage 3 rebuilds what stage 2 already built once:

    libaio: curl: (22) The requested URL returned error: 404
            https://pagure.io/libaio/archive/libaio-0.3.113/...tar.gz

The package sits in repo2 -- it was built when that URL answered. pagure.io is
still up (200 on the project page) and simply no longer generates archives at
that path. Arch has already moved to another spelling of it, at pkgrel 5; that
one returns 404 as well.

**Pinning protects reproducibility and freezes a URL at the same time.**
upstream.lock holds libaio at the commit that names a path which has ceased to
exist. The pin is doing exactly its job, and the job has stopped being enough.

**The Debian source is NOT the same file.** libaio_0.3.113.orig.tar.gz is
served, 49 980 bytes, and its sha512 does not match the one the PKGBUILD
carries. Substituting it and moving on would be borrowing a stranger's tarball
under a name that promises otherwise -- especially here, where builds run with
integrity checks off and nothing downstream would notice.

**To close: a local mirror of the sources.** Every tarball this port has ever
built from, kept beside the packages it produced. Not for speed -- for the day
an upstream reorganises, which has now happened once and will happen again. A
port whose sources live only on other people's servers is reproducible only for
as long as those servers agree.

Until then libaio can be installed and cannot be rebuilt, which is worth
knowing before someone counts on stage 3 being complete.

### A fourth failure shape: an interrupted download outlives the run

The three shapes above are about what a package needs. This one is about what
an earlier run left on disk. A kernel tarball stopped at 54 of 158 MB, and the
next run reported

    -> Found linux-7.1.10.tar.xz
    linux-7.1.10/Documentation/arch/x86/resume.svg: Truncated tar archive

because makepkg runs here with integrity checks off -- the patches this port
generates can never match upstream checksums -- so a short file IS the file.
The download error is in one log and the extraction error in the next, and they
name different things, which is what makes this shape worth naming.

**To close:** nothing to restore. A partial source is deleted, not built on top
of; `xz -t` answers in a second what a rebuild answers in fifteen minutes.

### A third failure shape: the host is behind

Contamination and closure gaps were the two known kinds. libxslt is neither:

    configure: error: Version 2.14.5 found. You need at least libxml2 2.15.1

2.14.5 is Ubuntu's libxml2; ours is 2.15.3. Nothing is contaminated and nothing
is missing — the package simply cannot be built on this host, at any point,
because the host is older than the package requires. It is built BY stage 2
instead of installed into it, and hoisted in `STAGE2_FIRST` so it precedes the
package that needs it. A stage-1 run is *expected* to report it as failed.

Worth watching for: any Arch package whose dependency floor has moved past
Ubuntu's version belongs in this category, and the error will always read like
a missing dependency rather than an old one.


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

### python-psutil has no test verdict -- `patches/pkgbuild/python-psutil.sh`

Its check() stops on `No module named pytest`, and pytest here is not one
package: python-pytest wants python-iniconfig, python-pluggy and
python-pygments, and python-pygments makedepends on python-sphinx,
python-hatchling and python-wcag-contrast-ratio. That is the same Sphinx tree
the llvm and clang hooks refused, reached by another road -- and iniconfig and
pluggy carry python-pytest in their OWN checkdepends, so it is circular as well
as large. checkdepends also name net-tools and procps-ng.

The build is untouched: the wheel is produced and packaged. And nothing here
needs the verdict -- llvm ran 68603 of its own tests at stage 2 without psutil
installed, and RESOLVE passes with the package absent from the repository.

**To close:** build the pytest chain when something else asks for it, and put
check() back.

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

**One exception, measured the same way and landing the other side of it.** The
four packages that lost man pages to DocBook -- pam, shadow, p11-kit, systemd
-- were never missing a TOOL: xsltproc is built here. They were missing DTDs
and stylesheets, and those are docbook-xml and docbook-xsl: zipped data, a few
xmlcatalog calls, arch=(any) for one of them, no compiler behind either. Both
are in the list now, straight after libxml2. It is also why postgresql needs no
hook -- `make world` builds its manuals from SGML, and now it can.

Note what they are NOT: converters. The `EXPAT_BUILD_DOCS` probe in expat
switches on when `docbook2man` and its siblings appear on PATH, which is how
expat began failing 29 hours after asciidoc pulled docbook-utils onto the host.
Data does not trip that probe, and nothing in these two packages lands on PATH.

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

### Never edit a script while it is running -- bash reads it as it goes

The stage-2 run that built llvm and clang ended on

    scripts/build-stage2.sh: line 1211: syntax error near unexpected token `fi'

after printing `2 rebuilt, 0 failed`. The file was fine -- `bash -n` passes.
What happened is that CHROOT_STAGE2_PKGS was edited while the script was
executing, and bash does not read a script into memory: it reads from a byte
OFFSET in the open file. Inserting three lines near the top shifted everything
after them, and when bash next read at its saved offset it landed mid-statement.

Nothing was lost here: the summary had printed, repo-add had run, the database
holds all 214 packages, and umount_chroot had already finished -- `findmnt`
shows nothing under rootfs-stage2. That last one is luck worth naming, because
a script killed BEFORE its unmount is exactly the state that let an earlier
`rm -rf` walk through a bind mount into the host /dev.

**The rule:** while a build is running, edit anything except the scripts that
are running. TODO.md, hooks not yet read, packages.sh for a future run -- all
fine. build-stage2.sh, bootstrap-pacman.sh -- wait.

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

## What ERPLibre still needs -- measured, from its own installer

`script/install/install_arch_linux.sh` in the ERPLibre tree is the authority
here, not a guess: it is the list ERPLibre itself installs on Arch. Checked
against repo and repo2.

Critical and missing: **postgresql**. Everything else the installer treats as
critical is already built -- git, wget, curl, openssl, zlib, xz, bzip2,
readline, sqlite, libffi.

**nodejs and npm are on that list and are not the answer either.** Read what
the installer does with them: `npm install -g rtlcss less`, and an `npm
install` for prettier -- and it marks both `(optionnel)` in their own error
paths. rtlcss builds right-to-left stylesheets; less compiles LESS, which Odoo
stopped using. Odoo 18 compiles its SCSS in Python: `libsass = "0.22.0"` sits
in ERPLibre pyproject.toml, and nothing in addons/ calls rtlcss.

The cost, if it were needed: nodejs is configured `--shared-` against ada,
c-ares, nghttp2, nghttp3, ngtcp2 and simdjson, none of which this port builds,
and npm wants jq. Eight packages for a stylesheet transform no one here runs.

What is real is narrower: the installer `exit 1`s if pacman cannot install
nodejs, even though everything it then does with it is optional. That is an
ERPLibre-side line to soften, not eight packages to build.

**To close:** build the shared libraries when something needs Node, or make
the installer treat nodejs the way it already treats what it installs with it.

**tk is on that list and is NOT one of the three.** The installer names it
among the pyenv build dependencies, where it means one thing: CPython builds
tkinter. Grepping the ERPLibre tree finds exactly two importers -- kdbx_manager.py,
which wraps the import in `try:` and does without, and selenium_lib.py, a test
helper that already assumes a browser and a screen. Neither runs a server.

Building it is not one package either: tk wants tcl and the X11 stack under it
-- xorgproto, libxau, libxdmcp, libxcb, libx11, libxext, libxrender, libxft,
fontconfig. That is a dozen packages so that a headless s390x can open a file
dialog it has no display for.

**To close, if ever:** build tk when something actually needs a GUI here.

Optional and missing: libzip, parallel, portaudio, cups, xmlsec, freetds,
libev, mariadb-libs, shfmt, postgis. The installer loops over those one name
at a time, precisely because pacman refuses an entire transaction over one
unknown name, so their absence does not stop an install.

A note for the rust chain: nodejs lands here anyway, so avoiding it in
libgit2 was not about keeping it out forever. libgit2 is built long before
nodejs could be -- a build dependency that early is a cycle, not a
convenience.

**Why the rust chain is not a detour.** ERPLibre poetry.lock has 362 packages,
and four of them are Rust extensions: cryptography, orjson, pydantic-core,
rpds-py. PyPI publishes no s390x wheel for them, so pip compiles all four from
source or installs none of them. rust is not an option here; it is the step
between a built distribution and a running ERPLibre.

ERPLibre builds its OWN Python -- 3.12.10, from `.python-odoo-version`, for
Odoo 18 -- rather than using the 3.14 this port carries for pacman and meson.
It builds it with pyenv, because there is no mise binary for s390x, which means
compiling CPython: gcc, zlib, bzip2, readline, sqlite, openssl, libffi, xz,
ncurses. All of them are built. `EL_PIP_PROVIDER=auto` will find no uv for
s390x either and fall back to pip, which is the path that needs rust.

**IT RUNS.** Odoo 18.0 serves its web interface on this port, against our own
PostgreSQL. What was measured, not inferred:

    /web/login              200, <title>Odoo</title>
    /web/database/list      200, {"result": ["odoo_test"]}
    /jsonrpc search_read    {"result": [{"id": 2, "login": "admin",
                                         "name": "Administrator"}]}

That last one is an authenticated ORM read over JSON-RPC -- the whole stack,
end to end. The database behind it: PostgreSQL 18.6 on s390x-ibm-linux-gnu,
compiled by gcc 16.2.1, holding 121 tables, 140 models, 12 installed modules.
CPython 3.12.10 built by pyenv against our glibc 2.44, and every wheel compiled
from source: cryptography, orjson, pydantic-core and rpds-py through rust,
psycopg2 through our postgresql, lxml through our libxml2 and libxslt, pillow
through libjpeg-turbo, pikepdf through qpdf.

### What is NOT proven, and should not be read as though it were

- ~~**ERPLibre addons.**~~ **Tested, not argued.** 127 of the 129 addon
  repositories are on github.com and were cloned AT THE COMMITS the reference
  checkout pins -- 127 clones, 0 failures. Odoo then discovered 2574 manifests
  across a 118-entry addons_path, and ERPLibre own module went in:

      erplibre_info                        installed
      ir.module.module search_count        3249

  read back through JSON-RPC, not from the log. The one repository left out
  lives on git.bemade.org and needs credentials this port has no business
  holding.
- **mysqlclient.** ERPLibre pyproject.toml carries it as a NON-optional
  dependency, and PyPI publishes only Windows wheels, so it always compiles and
  always wants MariaDB client headers. Arch has no standalone
  mariadb-connector-c: mariadb-libs comes only from the whole mariadb pkgbase,
  which pulls boost, jemalloc, judy and cracklib, and clones rocksdb, duckdb and
  columnstore. Hours of C++ for a MySQL client in a PostgreSQL application. Set
  aside on instruction, and worth raising ERPLibre-side: its own Arch installer
  marks mariadb-libs optional while poetry cannot finish without it.
- ~~**systemd, a real boot.**~~ **Booted, and it comes back on its own.** The
  port's own kernel -- 7.1.10-arch1-1, compiled by this port's gcc 16.2.1 and
  binutils 2.47 -- boots a 24 GB ext4 image over virtio-blk-ccw under QEMU and
  reaches multi-user in under six seconds. sshd binds 0.0.0.0:22, because the
  kernel registers PF_INET; from inside, DNS resolves and
  `curl https://pypi.org/simple/` answers 200 against a bundle of 121
  certificates. postgresql and odoo are systemd units, both `enabled`, and
  after `systemctl poweroff` and a fresh start NOTHING is typed in the guest:
  `/web/login` answers 200 and the database list still names odoo_erplibre.
  No unit fails and `systemctl is-system-running` reports `running`, which is
  what BINFMT_MISC bought. `scripts/run-vm.sh` is the launcher.
- **nginx, and any inbound service that is not hostfwd.** The guest reaches the
  network through `-netdev user`, which gives outbound and two forwarded ports
  and nothing else. No bridge, no reverse proxy, no TLS termination.
- ~~**The CA bundle is generated in the guest.**~~ **The image build does it**
  -- `scripts/build-image.sh`. `pacman --root` runs no scriptlets, and the
  three that matter are not optional: without update-ca-trust every TLS client
  fails on `error adding trust anchors`, without ssh-keygen -A sshd will not
  start, and without systemd-sysusers pacman itself refuses to run for want of
  the `alpm` account -- as does initdb, for want of `postgres`. The host is
  s390x, so a chroot runs the guest's own binaries and closes all three at
  build time. Measured on an image built from nothing: boots in 3.5 s,
  `is-system-running` reports running with no failed unit, DNS resolves and
  pypi answers 200.
- ~~**Stage 3.**~~ **Reproduced, and measured.** Stage 3 builds from repo2
  alone and stage 4 from repo3 alone, 228 of 229 each -- the one absence being
  libaio, whose source is withdrawn upstream. Stage 4 against stage 3: 280
  packages both sides, every version equal, 279 identical contents of 280. The
  single difference is meson's build date inside its dev version string. A
  stage built from the previous one reproduces the previous one, which is what
  self-hosting means. `REPRODUIRE.md` carries the commands and the traps.
