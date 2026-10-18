#!/usr/bin/env bash
# Bootstrap the Arch packaging toolchain (pacman, makepkg, repo-add) on an
# s390x host, then build official Arch PKGBUILDs for s390x.
#
# WHY THIS IS THE KEYSTONE
#
# The README lists "pacman, bash and GNU coreutils are not yet ported" as three
# missing pieces. They are not three tasks -- pacman is the only one that
# matters, because pacman's source tree also ships makepkg and repo-add. Once
# those three run, every remaining package stops being hand-work and becomes
# `makepkg` on the upstream PKGBUILD.
#
# NO CROSS-COMPILATION IS NEEDED HERE. This runs on native s390x hardware, so
# the whole userspace builds at full speed with the host toolchain. That drops
# the z/VM round-trip the other scripts need.
set -euo pipefail

HERE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_DIR="${PATCH_DIR:-$HERE_DIR/../patches/pkgbuild}"
WORK="${WORK:-$HOME/work/arch-s390x}"
REPO="${REPO:-$WORK/repo/s390x}"
PACMAN_GIT="https://gitlab.archlinux.org/pacman/pacman.git"
# SURCHARGEABLE, parce qu un seul hôte sert les 229 recettes.
#
# Quand il tombe -- mesuré : aucune réponse ICMP, 443 fermé, pendant que
# GitHub et GNU répondaient en 200 ms -- tout paquet dont la recette n est
# pas déjà clonée s arrête. Un miroir local de dépôts nus se branche ici :
#
#   PKG_GIT_BASE="file://$HOME/work/arch-s390x/recettes-arch-s390x" \
#       bash scripts/build-stage1.sh
#
# Le miroir se fabrique avec un clone --mirror par recette ; ce qui compte
# est qu il porte les commits d upstream.lock, pas seulement les HEAD du jour.
PKG_GIT_BASE="${PKG_GIT_BASE:-https://gitlab.archlinux.org/archlinux/packaging/packages}"

log() { printf '\n== %s ==\n' "$*"; }

install_host_deps() {
    log "Host build dependencies"
    # Two distinct groups, and confusing them costs hours.
    #
    # makepkg's OWN requirements: bsdtar and fakeroot. Without them it fails
    # deep inside extraction with a bare "bsdtar: command not found".
    #
    # The PKGBUILDs' makedepends: --nodeps tells pacman not to check them, so
    # every one must be satisfied from the Ubuntu host by hand. Each name on
    # the last three lines was added because a build stopped on it --
    # systemtap-sdt-dev and gmp/mpfr/mpc for glibc and gcc, autopoint and
    # gperf for coreutils, asciidoc for pacman, po4a for xz, gnat for gcc's
    # Ada front end, debuginfod and jansson for binutils.
    #
    # binutils-dev, for llvm. LLVMgold includes <plugin-api.h>:
    #
    #   gold-plugin.cpp:39:10: fatal error: plugin-api.h: No such file
    #
    # It looked at first like fallout from disabling gold in our binutils, and it
    # is not: our binutils package SHIPS plugin-api.h at both stages -- checked --
    # so LLVMgold builds correctly in the chroot. Only the host was missing it,
    # because Ubuntu keeps that header in binutils-dev and nothing had asked for
    # it before.
    #
    # THE LIST WAS ALSO A LIE BY OMISSION. An audit of the six packages that
    # follow found libreadline-dev, libncurses-dev, zlib1g-dev, python3-dev,
    # doxygen, xsltproc, docbook-xsl, elinks and libcap2-bin already present
    # on the build VM but installed BY HAND, never declared here. On this
    # host they made the builds pass; on a fresh Ubuntu they would have
    # failed at readline, at libxml2 and inside shadow's `make install`, for
    # reasons that have nothing to do with s390x. They are named below now.
    # The rest is per-package, and each group says which package needs it.
    #
    #   gnupg     imagemagick + fig2dev render doc/*.svg and doc/*.fig, which
    #             a git checkout must generate; librsvg2-bin guarantees the
    #             SVG coder even under --no-install-recommends.
    #   shadow    itstool builds the translated man pages; libcap2-bin gives
    #             the bare `setcap` its install rule calls.
    #   util-linux  asciidoctor -- Ruby, and NOT the `asciidoc` above, which
    #             is a different program added for pacman. Easy to mistake
    #             for coverage.
    #   pam       libnsl/libtirpc for NIS, the DocBook 5 catalog, and elinks,
    #             which meson uses to dump the HTML manuals to text.
    #   brotli    cmake, and the PEP 517 chain its python bindings build with.
    #   libxml2   ICU, readline, and the doc toolchain.
    #   systemd   the widest surface of anything in stage 1; every one of
    #             these was checked against a real meson configure.
    #
    # The last two lines are the closure round, and every one of them was
    # named by a build that stopped: popt by cryptsetup, scdoc by kmod,
    # libgpg-error by libgcrypt, Cython by libseccomp, tcl by sqlite, argon2
    # by openldap, autoconf-archive by tpm2-tss and ducktype by dbus.
    #
    # A note on checking these. `apt-cache policy` was reporting NONE for all
    # eight, which looked like eight wrong names. This host answers in French:
    # the field is `Candidat :`, not `Candidate:`, so a grep for the English
    # word found nothing. Exactly the trap that broke util-linux's build --
    # met again while verifying the fix for it. Query apt under LC_ALL=C.
    #
    # The last line is the round after that, and each fix uncovered the next:
    # yelp-build by dbus (once ducktype was found), lmdb by krb5 (once the ss
    # flag was gone), cmocka by tpm2-tss (once autoconf-archive fixed its
    # macros). A build that gets further is progress even when it still fails.
    #
    # libsodium-dev replaced libargon2-dev, which was a wrong guess: openldap
    # passes `--with-argon2=libsodium`, so argon2.h was never what it wanted.
    # The error named argon2 and the answer was sodium -- the message pointing
    # at the wrong library, one more time.
    #
    # verto by krb5 and uthash by tpm2-tss came the round after, each once its
    # predecessor was satisfied. Three rounds of this taught one thing worth
    # writing down: when a package stops on a missing TOOL three times in a
    # row, stop installing tools. dbus wanted ducktype, then yelp-build, then
    # qhelpgenerator -- and the third needs Qt, so the chain had no end. Its
    # doc features are pinned off in a hook instead. A single missing library
    # is a host dep; a queue of them is a feature that should be disabled.
    #
    # The closure's second round wanted three more, and each named a program
    # rather than a library: asn1Parser by p11-kit (libtasn1-bin -- we build
    # the libtasn1 PACKAGE, but the host needs the TOOL), libevent by
    # libverto, libaio by lvm2.
    #
    # libsasl asked for a fourth and did not get it. Its error said
    # "libpq-fe.h: No such file or directory" while the header sat in
    # /usr/include/postgresql, and mysql.h sat in /usr/include/mariadb -- two
    # files that exist, on paths configure does not try. By the rule above,
    # that is a queue, so the SQL auxprop plugin is disabled in a hook
    # instead. Arch declares depends=(glibc) for libsasl and says why: the
    # plugins are dlopened, so nothing is lost.
    #
    # mercurial is for nss, whose only source is an hg clone of Mozilla's NSS
    # repository. gyp, perl and python were already here.
    #
    # libnspr4-dev is nss's other half: its build hardcodes -I/usr/include/nspr
    # and stops on `plarena.h: No such file or directory`. We DO build an nspr
    # package -- 4.40, newer than the host's 4.36 -- but this is an ABSENCE on
    # the host, not an age, so the ordinary stage-1 rule applies and the host
    # package is the answer. The libgcrypt hook exists precisely because that
    # rule did not apply there: 1.51 against a floor of 1.56 cannot be fixed
    # by installing anything.
    #
    # glib and libsecret are git's, for contrib/credential/libsecret. git is in
    # stage 1 only because STAGE 2 needs it: 51 of the 159 PKGBUILDs take their
    # sources from git+https, and makepkg validates that clone even under
    # --noextract. Nothing in the repository depends on git.
    #
    # libmpdec-dev is python's, and it is not optional: Python 3.13 removed the
    # vendored libmpdec, so --with-system-libmpdec is the only way to build and
    # it needs the system headers. Without them the failure is
    #
    #   No rule to make target 'Modules/_decimal/libmpdec/basearith.h'
    #
    # nine hundred lines into a PGO build -- a missing header reported as a
    # missing make rule for a file that used to be vendored.
    #
    # The last line is the meson/cmake round, and every entry is a tool those
    # two need to describe themselves: setuptools-scm and yaml for meson's own
    # build, sphinx for libuv's docs, rhash and nlohmann-json for cmake and
    # cppdap. Note what they are NOT: none is a dependency of the software
    # being ported. They are the cost of the build system, which is why the
    # dependency resolver never mentioned one of them.
    #
    # strictyaml, not yaml: meson's docs/meson.build asks for the module by
    # name and PyYAML does not answer to it. `python3-yaml` was installed
    # first, the error did not move, and only makedepends said which one --
    # `python-strictyaml`. Reading the PKGBUILD would have been quicker than
    # reading the error.
    #
    # cmake asked for four of these one at a time -- rhash, then jsoncpp, then
    # cppdap -- because its bootstrap prefers a system copy of everything it
    # bundles. That is a queue, and the rule says a queue is a feature to
    # disable. It is not applied here for once, and deliberately: each one
    # exists as an Ubuntu -dev package, so the queue terminates. The rule is
    # about queues with no end, like dbus asking for a third documentation
    # tool that needed Qt.
    # FOUR TOOLS NAMED BY WHAT FAILED WITHOUT THEM, not by guesswork:
    #   patchelf        curl's package() calls it by name
    #   gtk-doc-tools   libpsl's autoreconf runs gtkdocize
    #   systemd-dev     util-linux's meson asks pkg-config for `systemd`;
    #                   libsystemd-dev ships libsystemd.pc, not systemd.pc
    #   libnpth0-dev    gnupg's configure stops on "Required libraries not
    #                   found" and names npth in the lines above it
    #   libunistring-dev  gnutls' configure stops on "library containing
    #                   u8_normalize... no", which names a symbol, not a package
    #
    # python-is-python3, AND WHY IT IS NOT OPTIONAL.
    #
    # On Arch, `python` IS python3; Ubuntu ships only `python3`. Several
    # recipes call the bare name -- gcc among them, in package_gcc(). The
    # compile then succeeds ENTIRELY and packaging dies on one of its last
    # lines, hours in:
    #
    #   PKGBUILD: line 326: python: command not found
    #
    # which reads like a missing interpreter rather than a missing alias.
    sudo apt-get -o DPkg::Lock::Timeout=600 install -y -qq \
        meson ninja-build pkg-config gettext \
        libarchive-dev libcurl4-openssl-dev libgpgme-dev libssl-dev \
        libarchive-tools fakeroot \
        build-essential autoconf automake libtool m4 patch texinfo bison flex \
        zstd xz-utils bzip2 \
        systemtap-sdt-dev asciidoc autopoint gperf help2man rsync \
        binutils-dev \
        libgmp-dev libmpfr-dev libmpc-dev python3-docutils \
        libseccomp-dev libpcre2-dev \
        po4a gnat libdebuginfod-dev libjansson-dev \
        libreadline-dev libncurses-dev zlib1g-dev python3-dev \
        doxygen xsltproc docbook-xsl libcap2-bin \
        imagemagick fig2dev librsvg2-bin \
        itstool asciidoctor \
        libtirpc-dev libnsl-dev docbook5-xml docbook-xsl-ns elinks \
        cmake python3-build python3-installer python3-pkgconfig \
        python3-setuptools python3-wheel python-is-python3 \
        patchelf gtk-doc-tools systemd-dev libnpth0-dev libunistring-dev \
        libicu-dev \
        libbpf-dev clang libapparmor-dev libfdisk-dev libkmod-dev libdw-dev \
        libpwquality-dev libxkbcommon-dev libdbus-1-dev libqrencode-dev \
        libfido2-dev libtss2-dev libmicrohttpd-dev libaudit-dev \
        libcryptsetup-dev libgcrypt20-dev libgnutls28-dev libpam0g-dev \
        libpopt-dev scdoc libgpg-error-dev cython3 tcl-dev libsodium-dev \
        autoconf-archive ducktype \
        yelp-tools liblmdb-dev libcmocka-dev libverto-dev uthash-dev \
        libtasn1-bin libevent-dev libaio-dev mercurial libnspr4-dev \
        libglib2.0-dev libsecret-1-dev libmpdec-dev \
        python3-setuptools-scm python3-yaml python3-sphinx \
        librhash-dev nlohmann-json3-dev python3-strictyaml libjsoncpp-dev \
        libcppdap-dev
    install_host_shims
}

# The parts of "make the host look enough like Arch" that apt cannot express.
#
# Called from install_host_deps AND from build-stage1.sh, deliberately. The
# stand-ins are only consulted through /usr/local/bin, so editing the copy in
# this repository changes NOTHING until it is installed -- and a stale
# /usr/local copy is invisible: the build succeeds and ships the wrong paths.
# Re-installing them on every stage-1 run makes the repository the source of
# truth in fact, not just in intent. Both operations are idempotent.
install_host_shims() {
    log "Host shims"
    local d="$HERE_DIR/devtools"
    sudo install -m755 "$d/arch-meson" "$d/arch-cmake" /usr/local/bin/
    # history.pc, which Ubuntu drops and Arch ships.
    #
    # GNU readline generates and installs BOTH readline.pc and history.pc;
    # Debian and Ubuntu keep the first and delete the second, while the
    # library, libhistory.so, is right there in libreadline-dev. libxml2 asks
    # pkg-config for `history` and stops:
    #
    #   libxml2/meson.build:353:18: ERROR: Dependency "history" not found
    #
    # THE TRAP: our own readline package in repo/s390x DOES ship a correct
    # history.pc, so copying that one looks like the tidy answer. It is not.
    # Its libdir is ${exec_prefix}/lib -- right for the target rootfs, wrong
    # for a multiarch host where /usr/lib holds no libhistory. The .pc has to
    # describe THIS host, so it is generated from the host's own readline.pc.
    local multiarch version
    multiarch="$(dpkg-architecture -qDEB_HOST_MULTIARCH)"
    version="$(pkg-config --modversion readline)"
    sudo mkdir -p /usr/local/lib/pkgconfig
    printf '%s\n' \
        "prefix=/usr" \
        "exec_prefix=\${prefix}" \
        "libdir=/usr/lib/$multiarch" \
        "includedir=\${prefix}/include" \
        "" \
        "Name: History" \
        "Description: GNU History library" \
        "Version: $version" \
        "Requires.private: tinfo" \
        "Libs: -L\${libdir} -lhistory" \
        "Cflags: -I\${includedir}" \
        | sudo tee /usr/local/lib/pkgconfig/history.pc > /dev/null
    pkg-config --exists history || {
        echo "history.pc still not visible to pkg-config" >&2; return 1; }

    # THE CLASSIC INCLUDE LAYOUT, WHICH MULTIARCH NO LONGER PROVIDES.
    #
    # Debian and Ubuntu file the architecture-dependent headers under
    # /usr/include/<triplet>: asm/ from the kernel headers, bits/ and gnu/ from
    # libc, sys/sdt.h from systemtap. gcc finds them because its own search
    # path knows the triplet. glibc does not: it compiles with -nostdinc and
    # one -isystem /usr/include, so the first generated header stops it:
    #
    #   bits/sigcontext.h:30: fatal error: asm/sigcontext.h: No such file
    #
    # naming the architecture of the machine it is running on. A symlink per
    # name is the bridge, and only stage 1 needs it -- stage 2 onwards build
    # inside an Arch root where the layout is already classic.
    #
    # Links, not copies: the headers must track the packages that own them.
    # Each is skipped when a real directory already sits there, so a host that
    # files them classically is left alone.
    local _t _n _f
    _t="$(dpkg-architecture -qDEB_HOST_MULTIARCH)"
    for _n in asm bits gnu; do
        [ -e "/usr/include/$_n" ] && continue
        [ -d "/usr/include/$_t/$_n" ] || continue
        sudo ln -sfn "/usr/include/$_t/$_n" "/usr/include/$_n"
        say_shim "/usr/include/$_n -> $_t/$_n"
    done
    # sys/ IS NOT LIKE THE OTHERS: it already exists, and other -dev packages
    # own files in it (acl.h, capability.h). A directory symlink would hide
    # them, so each missing header is linked on its own.
    #
    # ALL of them, not the one that just failed. Linking sdt.h alone gets as
    # far as its own first line:
    #
    #   /usr/include/sys/sdt.h:246: fatal error: sdt-config.h: No such file
    #
    # and every header behind that one waits its turn. Bridging the directory
    # contents closes the class instead of its first instance.
    if [ -d "/usr/include/$_t/sys" ]; then
        sudo mkdir -p /usr/include/sys
        _n=0
        for _f in "/usr/include/$_t/sys/"*.h; do
            [ -e "$_f" ] || continue
            [ -e "/usr/include/sys/${_f##*/}" ] && continue
            sudo ln -sfn "$_f" "/usr/include/sys/${_f##*/}"
            _n=$((_n + 1))
        done
        [ "$_n" -gt 0 ] && say_shim "/usr/include/sys: $_n header(s) linked from $_t"
    fi
    # The bridge is load-bearing: glibc is the second package stage 1 builds,
    # and nothing after it survives its absence.
    [ -e /usr/include/sys/sdt-config.h ] || [ ! -e "/usr/include/$_t/sys/sdt-config.h" ] || {
        echo "host shims: sys/ was not bridged" >&2; return 1; }
    [ -e /usr/include/asm/sigcontext.h ] || {
        echo "host shims: asm/ is still not reachable from /usr/include" >&2
        echo "  looked for /usr/include/$_t/asm" >&2
        return 1
    }
}

say_shim() { printf "  %s\n" "$*"; }

build_pacman() {
    log "pacman + makepkg + repo-add"
    mkdir -p "$WORK"
    [ -d "$WORK/pacman" ] || git clone --depth 1 "$PACMAN_GIT" "$WORK/pacman"
    cd "$WORK/pacman" || return 1
    # /usr/local, never /usr: this host is Ubuntu and /usr belongs to dpkg.
    # makepkg resolves its own libraries from the configured prefix, so the
    # prefix has to be real -- running it from the build tree fails with
    # "/usr/share/makepkg/*.sh: No such file or directory".
    rm -rf build
    meson setup build --prefix=/usr/local --buildtype=release \
        -Ddoc=disabled -Ddoxygen=disabled -Di18n=false
    ninja -C build -j"$(nproc)"
    sudo ninja -C build install
    # THE LIBRARY IS INSTALLED AND THE BINARY STILL DOES NOT START.
    #
    # meson puts libalpm under /usr/local/lib/<triplet>, which ld.so already
    # searches -- but through a CACHE that still lists the distribution's older
    # libalpm. The freshly built pacman then dies on
    #
    #   /usr/local/bin/pacman: error while loading shared libraries:
    #   libalpm.so.16: cannot open shared object file
    #
    # naming a file that exists, in a directory that is configured. Refreshing
    # the cache is the whole fix, and nothing else does it.
    sudo ldconfig
    pacman --version >/dev/null 2>&1 || {
        echo "bootstrap-pacman: pacman is installed and does not run" >&2
        echo "  $(command -v pacman || echo 'not in PATH')" >&2
        exit 1
    }
}

configure_makepkg() {
    log "makepkg configuration"
    # CARCH is already detected as s390x by meson; CHOST must stay the
    # auto-detected triplet -- configure scripts are matched against it, and
    # inventing "s390x-pc-linux-gnu" breaks them.
    sudo sed -i "s|^#\?MAKEFLAGS=.*|MAKEFLAGS=\"-j$(nproc)\"|" /etc/makepkg.conf
    # SOURCES KEPT, the same directory stage 2 and later use through their
    # bind mount. Stage 1 builds on the host, so its downloads would otherwise
    # land in each recipe directory and be lost with it -- and an upstream that
    # stops serving a tarball takes that package's reproducibility with it.
    sudo install -d -o "$(id -u)" -g "$(id -g)" "$WORK/pkg/.sources"
    sudo sed -i "s|^#\?SRCDEST=.*|SRCDEST=$WORK/pkg/.sources|" /etc/makepkg.conf
    grep -q '^SRCDEST=' /etc/makepkg.conf ||
        echo "SRCDEST=$WORK/pkg/.sources" | sudo tee -a /etc/makepkg.conf >/dev/null
    # pacman refuses to initialise alpm without its database directory. The
    # error is only a warning during packaging, but it hides real ones.
    sudo mkdir -p /var/lib/pacman
    # Arch's numeric group ids must EXIST on the build host.
    #
    # The filesystem package creates directories with `install -g 11`, and
    # GNU coreutils rejects a gid that resolves to nothing:
    #
    #   install: invalid group: '11'
    #
    # gid 11 is `ftp` on Arch; Ubuntu leaves it free. This is the circular
    # corner of any bootstrap -- the package that DEFINES /etc/group needs
    # groups that do not exist yet -- and the way out is to give the build
    # host the target's id map rather than to work around the check.
    #
    # Only the ids Arch uses and Ubuntu lacks are created, and only when
    # missing, so an already-correct host is left alone.
    if ! getent group 11 > /dev/null 2>&1; then
        sudo groupadd -g 11 ftp
        echo "created group ftp (gid 11), required by the filesystem package"
    fi
    # CHOST must be the CANONICAL triplet, not the Debian-style one.
    #
    # gcc -dumpmachine reports s390x-linux-gnu here, but config.sub
    # canonicalises that to s390x-ibm-linux-gnu, and GCC builds its tree
    # under the canonical name. Arch PKGBUILDs assume the canonical form --
    # theirs is x86_64-pc-linux-gnu, with the vendor field present -- so
    # gcc's own PKGBUILD looked for $CHOST/libstdc++-v3/doc and found
    # nothing:
    #
    #   make: *** s390x-linux-gnu/libstdc++-v3/doc: No such file or directory
    #
    # while the build had created s390x-ibm-linux-gnu/libstdc++-v3/doc.
    sudo sed -i 's|^CHOST=.*|CHOST="s390x-ibm-linux-gnu"|' /etc/makepkg.conf
    # OPTIONS, aligned with Arch's own defaults.
    #
    # This host was configured with `libtool staticlibs`, which KEEPS the .la
    # files and the .a archives that Arch strips. Fifty-six of a hundred and
    # fifty-nine packages carried .la files as a result -- a third of the
    # repository diverging from Arch in a way nothing reported, until two
    # sub-packages of the same source both claimed one:
    #
    #   error: failed to commit transaction (conflicting files)
    #   /usr/lib/libcrypt.la exists in both 'libxcrypt' and 'libxcrypt-compat'
    #
    # That is what .la files are for: they record a link line, so two packages
    # splitting one library both want to describe it. Arch removes them
    # because nothing in a modern toolchain reads them and the paths they
    # record are wrong the moment a package is relocated.
    #
    # debug and lto stay OFF, unlike Arch: debug wants a source-package
    # pipeline this bootstrap has no use for, and lto doubles compile time on
    # a stage whose output stage 2 discards anyway. autodeps stays off because
    # it is makepkg's own default; TODO.md records what that costs.
    sudo sed -i 's|^OPTIONS=.*|OPTIONS=(strip docs !libtool !staticlibs emptydirs zipman purge !debug !lto !autodeps)|' /etc/makepkg.conf
    grep -E '^(CARCH|CHOST|MAKEFLAGS|OPTIONS)=' /etc/makepkg.conf
}

# build_package <name> -- fetch the official PKGBUILD and build it for s390x.
#
# --ignorearch: upstream PKGBUILDs carry arch=(x86_64) and nothing else.
# CHECKSUMS ARE VERIFIED. --skipchecksums used to be passed here, justified
#   by GitLab regenerating .patch URLs so their sums drift. Measured instead
#   of assumed: `makepkg --verifysource` over the 148 recipes cloned on this
#   host passes 148 and fails 0. No recipe drifts, so nothing is skipped.
#
#   A recipe that does drift later will stop its own build with "One or more
#   files did not pass the validity check" -- loudly, naming itself. Give
#   that one entry SKIP in its own hook; do not turn the check off for all.
#
#   WHAT PASSING IT TURNED OFF, read from makepkg rather than assumed:
#
#     check_source_integrity() {
#       if (( SKIPCHECKSUMS && SKIPPGPCHECK )); then
#         warning "Skipping all source file integrity checks."
#
#   Both flags are passed here, so that first branch is the one taken: NO
#   source is verified -- not the patches, not the release tarballs, not the
#   signatures. An earlier version of this comment claimed the tarballs still
#   validated. They do not, and a reader who trusted that sentence would have
#   believed the port verified what it downloads.
#
#   The cost is paid far from here. makepkg reuses a cached source on its NAME
#   alone, so a truncated or substituted file in SRCDEST is used as-is, and a
#   hook that justifies changing a source URL by "same sha256" rests on a sum
#   this build never computes.
#
#   To close: keep checksums ON and let the few recipes with drifting patch
#   URLs carry SKIP on those entries alone. Measure first -- how many of the
#   235 actually drift is unknown, and probably small.
# --nocheck: stage-1 test suites run against the HOST libraries, not Arch's,
#   so their verdict says nothing about the port. acl failed its check() on a
#   perfectly sound build, and the suites cost hours. Stage 2 runs them.
build_package() {
    local name="$1"
    log "Building $name"
    # Free space, checked before the build rather than discovered inside it.
    #
    # A full disk does not say so. gcc's stage-2 bootstrap reported
    #
    #   genattrtab: cannot close file tmp-attrtab.cc: No space left on device
    #
    # seventeen thousand lines into its log, behind two hundred lines of make
    # recursion -- and the first grep for "error:" matched cpp_error(), a
    # function name in gcc's own source. Every symptom pointed at gcc.
    #
    # This host is shared with running VMs whose disk images grow, so the
    # margin is not stable and cannot be assumed. 8 GiB clears gcc, the
    # largest build here; a smaller package will simply never trip it.
    local free_mb
    free_mb=$(df -Pm "$WORK" | awk 'NR==2 {print $4}')
    if [ "${free_mb:-0}" -lt 8192 ]; then
        echo "only ${free_mb} MiB free under $WORK; need 8192" >&2
        echo "reclaim with: rm -rf $WORK/pkg/*/src   (makepkg -C re-extracts)" >&2
        return 1
    fi
    mkdir -p "$WORK/pkg"
    # Both guards are load-bearing, and their absence cost a whole run.
    #
    # gitlab.archlinux.org answers a 404 by asking for credentials, so a
    # package that does not exist fails as
    #
    #   fatal: could not read Username for 'https://gitlab.archlinux.org'
    #
    # GIT_TERMINAL_PROMPT=0 turns that into an immediate error instead of a
    # process waiting on a terminal that is not there.
    #
    # Then the cd. With neither guarded, a failed clone left makepkg running
    # in whatever directory the PREVIOUS package used -- it rebuilt that
    # package, wrote the output into THIS package's log, and copied the
    # artefact back into the repository. log-libselinux.txt was 119 KB of
    # util-linux. The lesson is the repository's oldest one, one level up:
    # an exit code proves nothing, and neither does a log file's NAME.
    # A RECIPE THIS REPOSITORY WRITES ITSELF IS NOT UPSTREAM'S.
    #
    # pkgbuild/<name>/ holds the PKGBUILDs no Arch package can provide -- zipl
    # exists only on this architecture, so there is nothing to clone and
    # nothing to diff against. Stage 2 has read them since it was written;
    # stage 1 did not, and asked gitlab for a project that does not exist:
    #
    #   fatal: could not read Username for 'https://gitlab.archlinux.org'
    #
    # which reads as a credentials problem, or a network one, and is neither.
    # Copied rather than cloned, and deliberately NOT a fallback for a failed
    # clone: a network error must not silently build something else.
    if [ -f "$HERE_DIR/../pkgbuild/$name/PKGBUILD" ]; then
        rm -rf "$WORK/pkg/$name"
        mkdir -p "$WORK/pkg/$name"
        cp -r "$HERE_DIR/../pkgbuild/$name/." "$WORK/pkg/$name/"
        echo "  local PKGBUILD for $name"
    elif [ ! -d "$WORK/pkg/$name" ]; then
        GIT_TERMINAL_PROMPT=0 \
            git clone --depth 1 "$PKG_GIT_BASE/$name.git" "$WORK/pkg/$name" || {
            rm -rf "$WORK/pkg/$name"
            echo "clone failed: $PKG_GIT_BASE/$name.git" >&2
            return 1
        }
    fi

    # Land on the commit this port was written against, not on today's.
    #
    # The clone above is --depth 1 of whatever HEAD happens to be. Every hook
    # under patches/pkgbuild/ asserts exact strings, so a version bump upstream
    # breaks them -- which is the hooks working as intended, and also the reason
    # a rebuild months from now would not reproduce this one.
    #
    # scripts/upstream.lock records one commit per checkout. When it names this
    # package, the checkout is put on that commit; when it does not, the build
    # proceeds on HEAD and SAYS SO, because an unlocked package is how the lock
    # quietly stops covering the port.
    if [ -f "$HERE_DIR/upstream.lock" ]; then
        local _sha
        _sha=$(awk -v n="$name" '$1 == n {print $2}' "$HERE_DIR/upstream.lock")
        if [ -n "$_sha" ]; then
            if [ "$(git -C "$WORK/pkg/$name" rev-parse HEAD 2>/dev/null)" != "$_sha" ]; then
                if git -C "$WORK/pkg/$name" fetch -q --depth 1 origin "$_sha" 2>/dev/null &&
                   git -C "$WORK/pkg/$name" checkout -q --detach FETCH_HEAD 2>/dev/null; then
                    echo "  pinned to ${_sha:0:9} (upstream.lock)"
                else
                    echo "  WARNING: cannot reach locked commit ${_sha:0:9}; using HEAD" >&2
                fi
            fi
        else
            echo "  NOTE: $name is not in upstream.lock; building against HEAD" >&2
        fi
    fi
    cd "$WORK/pkg/$name" || return 1
    # Port patches. Upstream PKGBUILDs are written for x86_64 and some carry
    # flags no other architecture accepts -- glibc's --enable-sframe is the
    # first. They are applied here, one hook per package, so each change is
    # visible, reviewable and survives a re-clone, rather than being an edit
    # someone once made by hand in a working copy.
    local hook="$PATCH_DIR/$name.sh"
    if [ -f "$hook" ]; then
        git checkout -- PKGBUILD 2>/dev/null || true
        # EL_STAGE tells the hook which stage is asking. Some hooks -- git,
        # meson, libgcrypt, libarchive -- exist partly or wholly to work around
        # something about the HOST, and that part must not run in the chroot
        # where the problem does not exist.
        EL_STAGE=1 bash "$hook" || return 1
    fi
    rm -f ./*.pkg.tar.*
    # Explicit `|| return 1`. Relying on `set -e` here does NOT work: callers
    # invoke build_package inside `if`, which disables set -e for the whole
    # function body. A failing makepkg then fell through to repo-add, whose
    # success became the function's exit status -- and a run reported
    # "51 built, 0 failed" while glibc, gcc, coreutils and pacman had all
    # failed. Measured: the repository held 23 files, not a hundred.
    # -C wipes $srcdir first. Without it a re-run inherits the previous
    # attempt's tree, and prepare() fails on work it already did:
    #   patch: ... already exists!  Skipping patch.
    #   1 out of 1 hunk ignored
    #   mkdir: build-curl-compat: File exists
    # grep, gnupg, pacman and curl all failed this way -- not on the
    # port, but on my own driver re-entering a dirty directory.
    # LC_ALL=C.UTF-8, because build systems parse their tools' output.
    #
    # This host runs LANG=fr_FR.UTF-8. util-linux's poman-translate.sh reads
    # po4a's report and skips what it says it discarded:
    #
    #   DISCARDED_TRANSLATION=$(echo "$line" | awk '/Discard/ {print $2;}')
    #
    # -- an English word matched against a gettext-translated message. In
    # French po4a prints "Rejet de ar/..." instead, so the skip list came out
    # empty, asciidoctor was handed 852 files po4a had never written, and the
    # build died on the first. Note $2 is "de" in French: even a locale-aware
    # pattern would take the wrong field.
    #
    # It went unseen for a second reason -- the script captures po4a in
    # `output=$(...)`, so none of those 852 lines reach the log at all.
    #
    # The locale is a property of THIS host, not of any one package, and any
    # build that greps English tool output is exposed. So it is pinned here,
    # once, rather than in a hook per package. C.UTF-8 and not C: the Arabic
    # and Ukrainian pages must stay valid UTF-8. Arch's own build chroot runs
    # in this locale, so this makes us match it rather than diverge.
    # DEB_PYTHON_INSTALL_LAYOUT=deb_system, because Debian's python installs
    # into /usr/local and an Arch package may not ship that tree.
    #
    #   $ python3 -c 'import sysconfig; print(sysconfig.get_default_scheme(),
    #                 sysconfig.get_path("purelib"), sysconfig.get_path("scripts"))'
    #   posix_local /usr/local/lib/python3.13/dist-packages /usr/local/bin
    #   $ DEB_PYTHON_INSTALL_LAYOUT=deb_system python3 -c '...'
    #   deb_system  /usr/lib/python3/dist-packages           /usr/bin
    #
    # Without it every wheel-installing PKGBUILD ships /usr/local, and the
    # filesystem package owns every path in there -- including
    # usr/local/share/man, which it ships as a SYMLINK. pacman then refuses the
    # whole transaction:
    #
    #   error: failed to commit transaction (conflicting files)
    #   /usr/local/share/man exists in both 'filesystem' and 'meson'
    #
    # Four packages hit this before it was fixed here rather than in each of
    # them: python-brotli and python-libseccomp (both dropped for other
    # reasons), meson and python-tqdm. Setting it once covers every python
    # package, including ones not built yet.
    #
    # It does NOT finish the job: deb_system still says dist-packages, and
    # Arch's python reads site-packages. That last move stays per-package,
    # because only the packages whose modules are actually IMPORTED on the
    # target need it -- meson does, and its hook does it.
    LC_ALL=C.UTF-8 \
    DEB_PYTHON_INSTALL_LAYOUT=deb_system \
    makepkg --nodeps --ignorearch --skippgpcheck --nocheck \
        -C -f || return 1
    # An exit code is not proof. Only the artefact is.
    local produced=()
    shopt -s nullglob
    produced=(./*.pkg.tar.*)
    shopt -u nullglob
    if [ "${#produced[@]}" -eq 0 ]; then
        echo "no package produced for $name" >&2
        return 1
    fi
    mkdir -p "$REPO"
    cp -f "${produced[@]}" "$REPO/" || return 1
    # Only the new packages. Globbing the whole repository made repo-add
    # re-index everything on every call: quadratic, and it buried the real
    # lines under warnings about entries that already existed.
    local names=() f
    for f in "${produced[@]}"; do names+=("$(basename "$f")"); done
    ( cd "$REPO" && repo-add core.db.tar.gz "${names[@]}" ) || return 1
}

main() {
    install_host_deps
    build_pacman
    configure_makepkg
    for p in "$@"; do build_package "$p"; done
    log "Done"
    command -v pacman makepkg repo-add
}

# Only run when executed, never when sourced: build-stage1.sh reuses
# build_package and must not re-run the whole bootstrap to get it.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
