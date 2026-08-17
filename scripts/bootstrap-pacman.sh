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
PKG_GIT_BASE="https://gitlab.archlinux.org/archlinux/packaging/packages"

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
    sudo apt-get -o DPkg::Lock::Timeout=600 install -y -qq \
        meson ninja-build pkg-config gettext \
        libarchive-dev libcurl4-openssl-dev libgpgme-dev libssl-dev \
        libarchive-tools fakeroot \
        build-essential autoconf automake libtool m4 patch texinfo bison flex \
        zstd xz-utils bzip2 \
        systemtap-sdt-dev asciidoc autopoint gperf help2man rsync \
        libgmp-dev libmpfr-dev libmpc-dev python3-docutils \
        libseccomp-dev libpcre2-dev \
        po4a gnat libdebuginfod-dev libjansson-dev \
        libreadline-dev libncurses-dev zlib1g-dev python3-dev \
        doxygen xsltproc docbook-xsl libcap2-bin \
        imagemagick fig2dev librsvg2-bin \
        itstool asciidoctor \
        libtirpc-dev libnsl-dev docbook5-xml docbook-xsl-ns elinks \
        cmake python3-build python3-installer python3-pkgconfig \
        python3-setuptools python3-wheel \
        libicu-dev \
        libbpf-dev clang libapparmor-dev libfdisk-dev libkmod-dev libdw-dev \
        libpwquality-dev libxkbcommon-dev libdbus-1-dev libqrencode-dev \
        libfido2-dev libtss2-dev libmicrohttpd-dev libaudit-dev \
        libcryptsetup-dev libgcrypt20-dev libgnutls28-dev libpam0g-dev
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
}

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
}

configure_makepkg() {
    log "makepkg configuration"
    # CARCH is already detected as s390x by meson; CHOST must stay the
    # auto-detected triplet -- configure scripts are matched against it, and
    # inventing "s390x-pc-linux-gnu" breaks them.
    sudo sed -i "s|^#\?MAKEFLAGS=.*|MAKEFLAGS=\"-j$(nproc)\"|" /etc/makepkg.conf
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
    grep -E '^(CARCH|CHOST|MAKEFLAGS)=' /etc/makepkg.conf
}

# build_package <name> -- fetch the official PKGBUILD and build it for s390x.
#
# --ignorearch: upstream PKGBUILDs carry arch=(x86_64) and nothing else.
# --skipchecksums: GitLab regenerates .patch URLs, so their checksums drift
#   from what the PKGBUILD recorded. Release tarballs still validate; only
#   the generated patches are skipped.
# --nocheck: stage-1 test suites run against the HOST libraries, not Arch's,
#   so their verdict says nothing about the port. acl failed its check() on a
#   perfectly sound build, and the suites cost hours. Stage 2 runs them.
build_package() {
    local name="$1"
    log "Building $name"
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
    if [ ! -d "$WORK/pkg/$name" ]; then
        GIT_TERMINAL_PROMPT=0 \
            git clone --depth 1 "$PKG_GIT_BASE/$name.git" "$WORK/pkg/$name" || {
            rm -rf "$WORK/pkg/$name"
            echo "clone failed: $PKG_GIT_BASE/$name.git" >&2
            return 1
        }
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
        bash "$hook" || return 1
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
    makepkg --nodeps --ignorearch --skippgpcheck --skipchecksums --nocheck \
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
