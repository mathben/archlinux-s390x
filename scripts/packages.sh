#!/usr/bin/env bash
# The package list, and the ORDER, shared by both stages.
#
# It lived in build-stage1.sh until stage 2 needed it. Stage 2 rebuilds the
# same packages inside the chroot, and the order it needs is not a new
# question: this one is the actual dependency closure, arrived at over four
# rounds of resolver output (35 unsatisfied, then 19, then 2, then none) and
# then confirmed by a hundred and ninety builds that each found their
# dependencies already present. Deriving a second order for stage 2 would be
# re-deriving a fact this file already holds -- and getting it subtly wrong
# would show up as a build failure attributed to the package rather than to
# the ordering.
#
# Sourced, never executed. Both stages read STAGE1_PACKAGES from here.

STAGE1_PACKAGES=(
    # Foundation: headers, then the C library, then the compiler chain.
    linux-api-headers glibc binutils gcc
    # Compression and crypto, needed by libarchive and curl further down.
    zlib bzip2 xz zstd lz4 openssl
    # Terminal handling: bash links against readline, readline against ncurses.
    ncurses readline
    # The shell, and the coreutils prerequisites Arch declares.
    attr acl gmp mpfr libcap bash coreutils
    # Text and file tools the build systems themselves call.
    sed grep gawk findutils diffutils file which patch
    # Archivers, then the library pacman reads packages with.
    tar gzip expat libarchive
    # Build systems.
    m4 autoconf automake libtool make pkgconf
    # pacman's network and signature stack.
    libnghttp2 libpsl curl libgpg-error libassuan gnupg gpgme
    # System skeleton: without these a rootfs has no /etc/passwd, no zones,
    # no /etc/services -- and nothing boots to a usable shell.
    filesystem iana-etc tzdata licenses shadow util-linux
    # Named by the chroot test, not guessed. Installing the repo into a
    # rootfs and entering it turned "does it work?" into a precise list:
    #   - libcap needs pam; openssl needs brotli; libarchive needs libxml2
    #   - pacman itself asks for systemd, pacman-mirrorlist and
    #     libmakepkg-dropins
    # Sixty-eight successful builds proved none of this. One chroot did.
    #
    # The chroot also named libselinux, and libselinux is NOT on this line,
    # because that reading of it was wrong. Arch has no libselinux package at
    # all -- the clone 404s. What the chroot saw was a HOST artefact: Ubuntu
    # carries libselinux1-dev, coreutils probes for selinux/selinux.h
    # unconditionally, and ours came out linked to a library the target will
    # never contain. The answer is --without-selinux per package, which is
    # what Arch's own build chroot gets for free by not having the header.
    pam brotli libxml2 systemd pacman-mirrorlist libmakepkg-dropins
    # The closure, named by pacman's own resolver rather than guessed.
    #
    # Everything above was added because a BUILD stopped. These were added
    # because scripts/test-chroot.sh ran `pacman -Syp` with --nodeps OFF --
    # the check the whole bootstrap skips -- and the resolver listed exactly
    # what the repository still owes. Nothing here is speculative.
    #
    # It is the MINIMAL closure, and two measurements shaped it. Dropping the
    # python-brotli sub-package took the list from 70 unresolved names to 47
    # and removed `python` outright, with libffi, mpdecimal and gdbm behind
    # it. Dropping systemd-ukify and systemd-tests removed five more python
    # packages, and ukify cannot run on s390x at all. Both are recorded in
    # TODO.md rather than left implicit.
    #
    # An audit of the remaining names against the ARTEFACTS found two that
    # were declared and never linked: guile by make, and libisl.so by gcc.
    # Both get their declaration removed, because it should describe the
    # binary we shipped.
    #
    # Building isl instead was the first plan, and it is recorded here because
    # the reason it failed is the kind that wastes an afternoon: the Arch
    # packaging repo for isl was last touched in 2017 and its only source URL
    # is isl.gforge.inria.fr, which died with INRIA's GForge. There is nothing
    # to build. That flipped the decision -- not a change of mind, new
    # evidence.
    #
    # These will pull their own dependencies. That is expected: the resolver
    # will name the next round as precisely as it named this one.
    audit ca-certificates cryptsetup dbus elfutils gettext gnutls hwdata
    icu jansson kbd kmod krb5 libcap-ng libgcrypt libidn2 libksba
    libmpc libnsl libseccomp libssh2 libtirpc libunistring libusb libxcrypt
    nettle npth openldap pambase pcre2 perl pinentry sqlite tpm2-tss
    # Closure, second round. The first thirty-five pulled these in, exactly as
    # the comment above predicted, and the resolver named them just as
    # precisely.
    #
    # THE MEASUREMENT THAT MATTERS HERE IS THE ONE THAT CHANGED ITS ANSWER.
    # Four of these were going to be avoided by dropping a sub-package --
    # sqlite-tcl, sqlite-analyzer, the openldap server, debuginfod -- on the
    # reasoning that had removed python-brotli earlier. Measured instead of
    # assumed, tcl, unixodbc and libmicrohttpd each cost ZERO new packages:
    # the closure had filled in around them. Building them is cheaper than
    # four hooks, and it does not leave sqlite shipping an sqltclsh that
    # cannot start.
    #
    # python still costs three (libffi, mpdecimal, gdbm) and is still avoided
    # -- but for the ABI reason, not the cost one: python-audit and
    # python-capng are cp313 wheels and Arch ships 3.14. Their hooks say so.
    #
    db5.3 gdbm e2fsprogs gnulib-l10n json-c keyutils p11-kit libsasl
    libsodium libtasn1 libverto lmdb popt lvm2 tcl unixodbc libmicrohttpd
    # ca-certificates-mozilla, which is the only thing here that is not a
    # library. It is the LIST OF ROOT CERTIFICATES -- ca-certificates itself
    # is only the trust machinery around it, so without this the target has a
    # trust store containing nothing, and every HTTPS verification fails.
    # curl declares ca-certificates, and pacman fetches through curl.
    #
    # It has no packaging repo of its own: the clone 404s, which
    # gitlab.archlinux.org reports by asking for a login -- the same
    # misleading shape that made libselinux look like a network problem. nss
    # produces it as a sub-package, so nss is what gets built, and nspr comes
    # with it.
    #
    # Measured before committing to it rather than estimated: nspr costs
    # nothing new, nss needs only nspr plus mercurial on the host, and
    # hg.mozilla.org answers from this build host (HTTP 302 in 0.3s -- worth
    # checking, since dev.gnupg.org does not answer at all and libassuan
    # needed a source change because of it).
    nspr nss
    # Closure, third round, and it is two packages. Both were pulled in by
    # what the second round added, and both cost nothing further: libffi by
    # libp11-kit, libevent by libverto.
    #
    # They are worth a line because of what they unblocked. p11-kit builds
    # into three packages, and libp11-kit's dependency on libffi was holding
    # up the whole chain ca-certificates -> ca-certificates-utils -> p11-kit
    # -> libp11-kit. The resolver reported it as "ca-certificates required by
    # curl" -- four links away from the missing name, and nothing in that
    # message points at libffi.
    libffi libevent
    # Closure, fourth round -- and it closed to NOTHING, which is the point
    # worth recording. It asked for libaio and thin-provisioning-tools, both
    # wanted by lvm2 alone. thin-provisioning-tools is Rust now, so that was a
    # language runtime arriving through a fourth-order dependency.
    #
    # Nothing in the repository wants `lvm2`. Checked across every .PKGINFO:
    # cryptsetup wants device-mapper, and device-mapper is the OTHER package
    # this same source produces. Dropping the lvm2 sub-package removed both
    # entries and the Rust question with them -- see patches/pkgbuild/lvm2.sh.
    #
    # 35 packages, then 19, then 2, then 0. The closure has to be recomputed
    # after each round rather than once: lvm2 DECLARED libaio all along, and
    # the third round could not see it because lvm2 had not been built yet.
    # What STAGE 2 needs in order to exist, which is a different question from
    # what the repository needs to resolve.
    #
    # Stage 2 rebuilds everything INSIDE the stage-1 rootfs, so the tools that
    # do the rebuilding have to be in that rootfs. The resolver never asked
    # for these -- nothing in the repository depends on them -- so the closure
    # rounds could not surface them. Enumerated instead from what makepkg and
    # an autotools build actually invoke.
    #
    # fakeroot is the one that decides whether stage 2 can start at all:
    # makepkg runs package() under it, and refuses to run as root. bison,
    # flex, texinfo and groff are what the sources themselves call -- gcc,
    # glibc and binutils all want makeinfo, and a great many configure scripts
    # want bison.
    #
    # sudo is deliberately NOT here. makepkg needs it only for --syncdeps, and
    # stage 2 passes --nodeps, so it would be a setuid binary in the chroot
    # for no reason.
    fakeroot bison flex texinfo groff
    # git, and it is not optional: 51 of the 159 PKGBUILDs take their sources
    # from a git+https URL, and makepkg re-validates that clone even with
    # --noextract. Without git in the chroot, stage 2 can rebuild a third of
    # the repository and no more.
    #
    # Its own three: perl-error, perl-mailtools (which brings perl-timedate)
    # and zlib-ng. Measured, not guessed -- and read from the depends array
    # rather than from my own tool, which had reported `zsh` as a dependency
    # of git. It is not; the tool's regex was catching a neighbouring array.
    perl-error perl-timedate perl-mailtools zlib-ng git
    # meson and cmake, which is where python re-enters -- and the distinction
    # matters, because dropping python earlier was not a mistake.
    #
    # At stage 1 the question was what the REPOSITORY must supply: python was
    # wanted only by python-brotli and python-libseccomp, wheels that Arch's
    # own python could not load anyway, so they went and python went with them.
    # Here the question is what the BUILD ENVIRONMENT must contain, and meson
    # is written in Python. Ten of the 159 PKGBUILDs call arch-meson; four call
    # cmake. Different question, different answer.
    #
    # Measured: mpdecimal, python, ninja, python-tqdm and meson, then cmake
    # with cppdap, jsoncpp, libuv, rhash and hicolor-icon-theme behind it.
    # Nothing further.
    mpdecimal python ninja python-tqdm meson
    cppdap jsoncpp libuv rhash hicolor-icon-theme cmake
    # And finally the package manager itself, built as an Arch package.
    pacman

    # Tools the STAGE-2 CHROOT needs, which the host supplied for free.
    #
    # Stage 1 never noticed these: install_host_deps put them there with apt,
    # and a build that finds its tool does not mention it. Inside the chroot
    # there is no apt and no host, so every one of them has to exist as a
    # package -- and the first thing stage 2 tried to rebuild stopped on
    #
    #   /bin/sh: line 1: rsync: command not found
    #   make[1]: *** [.../Makefile:1463: headers_install] Error 127
    #
    # from linux-api-headers, the first entry in this list. xxhash is here
    # because rsync links it.
    xxhash
    rsync
    # The rest of that same class, named by stage 2's first full pass rather
    # than guessed. 77 packages rebuilt, 57 failed, and fourteen of the
    # failures named the tool they wanted outright:
    #
    #   gperf      coreutils, diffutils, systemd, libseccomp
    #   wget       sed, grep, findutils
    #   patchelf   curl
    #   hostname   gnupg          (inetutils ships it)
    #   xsltproc   shadow         (libxslt ships it)
    #   swig       audit
    #   help2man   flex
    #
    # All small and self-contained. Three more tools were asked for and are NOT
    # here -- po4a, asciidoc's a2x, and asciidoctor -- because each brings a
    # language runtime (Perl module stack, Python, Ruby) to render
    # documentation. Those three packages get a hook instead, the same
    # arbitration as --auto-features auto.
    gperf
    wget
    patchelf
    inetutils
    libxslt
    swig
    help2man
)
