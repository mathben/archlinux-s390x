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
    # docbook-xml and docbook-xsl: DATA, not code. Zipped DTDs, XSL stylesheets
    # and a few xmlcatalog calls -- no compiler is involved, and docbook-xsl is
    # arch=(any). They are here because their ABSENCE is what cost pam, shadow,
    # p11-kit and systemd their man pages: those builds have xsltproc and are
    # missing what xsltproc reads. Eighteen hooks in this port disable a
    # documentation build; two data packages are a better trade than a
    # nineteenth, and postgresql keeps `make world` untouched because of them.
    #
    # Placed straight after libxml2, which builds the xmlcatalog docbook-xml
    # calls. pam is on the line ABOVE and so still builds before them -- that
    # one needs a reorder, not just a package, and is left for stage 3.
    docbook-xml docbook-xsl
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
    #   xsltproc   shadow         (libxslt ships it -- see below)
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
    swig
    help2man
    # help2man's own closure. Stage 1 builds with --nodeps, so help2man built
    # cleanly and was then UNINSTALLABLE -- populate stopped the whole of stage-2
    # pass two on
    #
    #   unable to satisfy dependency 'perl-locale-gettext' required by help2man
    #
    # which is the routine consequence of --nodeps and the reason RESOLVE exists
    # in test-chroot.sh: a build succeeding says nothing about whether the
    # repository is complete.
    perl-locale-gettext
    # Python packaging, which three stage-2 builds stopped on:
    #
    #   /usr/bin/python: No module named build
    #
    # brotli, libseccomp and meson build their wheels with `python -m build`,
    # and python-tqdm installs one. On the host these came from apt; in the
    # chroot they have to be packages. Ordered by their own dependencies:
    # flit-core bootstraps itself, then the two libraries build needs.
    # Of these seven, only python-flit-core builds on the host. The other six
    # compute their install paths from the running python, so the host bakes
    # Debian's dist-packages into them -- three failed on a `rm` that found
    # nothing, and three succeeded and shipped 180 unreachable module paths.
    # They are built by stage 2 instead; a stage-1 run is expected to report
    # them as failed, exactly like libxslt.
    python-flit-core
    python-packaging
    python-pyproject-hooks
    python-build
    python-installer
    python-setuptools
    python-wheel
    # scdoc: kmod's meson stopped on `Program 'scdoc' not found`. A man-page
    # generator, but a tiny self-contained C one -- nothing like the language
    # runtimes behind doxygen or asciidoctor, so it is cheaper to build than to
    # hook around.
    scdoc
    # nlohmann-json: a real closure gap, not a documentation cut. BOTH cmake and
    # cppdap stop on
    #
    #   Could NOT find nlohmann_json (missing: nlohmann_json_DIR)
    #
    # It is a header-only C++ library -- one of the cheapest packages in this
    # list -- and cmake is not optional here: the whole cmake/cppdap/jsoncpp/
    # libuv group behind it is what several other packages build with.
    nlohmann-json
    # python-vcs-versioning: setuptools-scm was split, and its own build now
    # imports the half that left:
    #
    #   from vcs_versioning import Configuration
    #   ModuleNotFoundError: No module named 'vcs_versioning'
    #
    # The traceback runs through setuptools' build_meta, so the visible error is
    # "Backend subprocess exited when trying to invoke build_wheel" -- a backend
    # complaint about a package that split upstream.
    # It is listed BEFORE python-setuptools-scm, which imports it while
    # building: the list is a build order, and a provider placed after its
    # consumer only works because a second pass picks it up.
    python-vcs-versioning
    # python-setuptools-scm: python-tqdm's build stops on
    #
    #   setuptools-scm[toml]>=3.4
    #
    # which is a requirements line, not an error message -- pip printing what it
    # could not find. Built by stage 2 with the rest of the Python set, for the
    # same reason: its package() would take Debian's dist-packages from the
    # host's python.
    python-setuptools-scm
    # systemd generates part of its source with jinja2 templates:
    #
    #   meson.build:1620:15: ERROR: python3 is missing modules: jinja2
    #
    # Not documentation -- the build cannot proceed without it. python-markupsafe
    # comes with it, as jinja's only dependency.
    python-markupsafe
    python-jinja
    # Three more the chroot asked for by name, each a build tool:
    #
    #   python-pkgconfig   brotli:     ERROR Missing dependencies: pkgconfig
    #                      -- the python MODULE, not pkg-config the program,
    #                      which has been there since the lib64 fix.
    #   cython             libseccomp: ERROR Backend subprocess exited when
    #                      trying to invoke get_requires_for_build_wheel
    #                      -- its python bindings are Cython.
    #   autoconf-archive   tpm2-tss:   configure.ac:139: error: undefined or
    #                      overquoted macro: AC_MSG_WARN
    #                      -- an AX_* macro is missing, so autoconf misreads the
    #                      line and blames one it does know.
    python-pkgconfig
    cython
    autoconf-archive
    # publicsuffix-list: DATA, not a tool. libpsl stops on
    #
    #   make: *** No rule to make target
    #     '/usr/share/publicsuffix/effective_tld_names.dat', needed by ...
    #
    # It compiles the Public Suffix List into a lookup table, so the list itself
    # is an input to the build. First entry in this port whose absence is neither
    # a program nor a library.
    publicsuffix-list
    # python-poetry-core: the fourth Python build backend this port has needed.
    # python-pkgconfig stops on
    #
    #   ERROR Backend 'poetry.core.masonry.api' is not available.
    #
    # flit_core, setuptools, hatchling and now poetry-core -- each package picks
    # its own, and each one has to exist before that package can be built.
    python-poetry-core
    # python-fastjsonschema: poetry-core validates pyproject.toml against a JSON
    # schema, so it needs a schema validator to build anything -- including
    # itself. ModuleNotFoundError: No module named 'fastjsonschema'.
    python-fastjsonschema
    # gyp: nss will not configure without it --
    #
    #   Building NSS requires an installation of gyp: https://gyp.gsrc.io
    #
    # Google's build-file generator, which nss uses to produce its ninja files.
    # A Python program, so it goes with the rest of the Python set.
    gyp
    # --- Rust, and what it needs ---------------------------------------------
    #
    # NOT optional, and that was measured rather than assumed. ERPLibre's
    # poetry.lock requires cryptography 46.0.5 with optional = false, plus jiter,
    # orjson, pydantic-core and rpds-py -- all of which build Rust from source
    # where no wheel exists, and none exists for s390x. Without Rust,
    # `pip install cryptography` fails and ERPLibre does not start.
    #
    # The bootstrap cycle is not the obstacle it looks like: rust-1.90.0 ships an
    # official s390x-unknown-linux-gnu tarball (verified, HTTP 200) and the host
    # already carries rustc 1.85.1. What costs is llvm and clang, which Arch's
    # rust lists as makedepends.
    #
    # libedit and python-psutil are all llvm and clang need beyond what is
    # already here -- Sphinx is disabled by their hooks, which removes some
    # fifteen documentation packages from the bill.
    libedit
    # python-psutil is a stage-2 package: built on the host it shipped 41
    # dist-packages paths, like every Python package whose install path comes
    # from the running interpreter. The ARTEFACT check caught it.
    python-psutil
    llvm
    # clang: expected to FAIL at stage 1, exactly as libxslt is, and for the
    # same shape of reason -- the host cannot supply a dependency we build
    # ourselves.
    #
    #   CMake Error at CMakeLists.txt:136 (message):
    #     llvm-gtest not found.  Please install llvm-gtest or disable tests
    #
    # MEASURED BEFORE CHOOSING: our llvm package ships 31 llvm-gtest files --
    # its PKGBUILD passes -DLLVM_INSTALL_GTEST=ON -- and the host has none.
    # So -DLLVM_INCLUDE_TESTS=OFF would be a hook treating a closure gap as a
    # configuration problem, and would silently drop what a stage-3 run with
    # the test suites enabled is supposed to exercise. clang is named in
    # CHROOT_STAGE2_PKGS instead: the chroot has our llvm, gtest included, and
    # configures with no hook at all.
    clang
    # libaio: a real closure gap. lvm2 stops on
    #
    #   device/bcache.c:30:10: fatal error: libaio.h: No such file or directory
    #
    # A small C library for asynchronous I/O, and one this port had already met
    # from the other side: Ubuntu renamed its runtime to libaio.so.1t64 for
    # time64, which was noted as a divergence long before anything needed the
    # headers.
    libaio
    # libxslt stays in the list because it is part of the distribution, but
    # STAGE 1 CANNOT BUILD IT:
    #
    #   configure: error: Version 2.14.5 found. You need at least libxml2
    #   2.15.1 for this version of libxslt
    #
    # 2.14.5 is Ubuntu's. Ours is 2.15.3 and exists only inside the stage-2
    # chroot, so that is the only place libxslt can come from -- it is in
    # STAGE2_FIRST, and a stage-1 run is expected to report it as failed.
    libxslt
    # The rust chain, in dependency order. All three are expected to FAIL at
    # stage 1, for the reason clang already documents: they are built against
    # OUR llvm 22, and the host has an older one.
    #
    # libgit2 is the exception that could build on the host, and is here for
    # order rather than necessity: cargo links it, and rust depends() on it.
    libgit2
    # lld is needed by rust twice over -- depends=(lld), and package_rust()
    # links usr/bin/{ld.lld,ld64.lld,lld-link,wasm-ld} into rustlib gcc-ld.
    lld
    # rust itself. Its stage0 is an upstream binary, which is worth saying out
    # loud; patches/pkgbuild/rust.sh says why there is no alternative.
    rust
    # What ERPLibre needs that this port did not already have: a database.
    #
    # numactl and liburing are postgresql's only missing dependencies, and both
    # are small enough that dropping the flags would be the odder choice --
    # numactl depends on glibc alone, liburing needs git to build and nothing
    # to link. postgresql 18 uses io_uring for asynchronous I/O, so --without
    # would be giving up a feature rather than avoiding a cost.
    numactl liburing
    # perl-io-tty and perl-ipc-run are not runtime dependencies of anything --
    # they exist because stage 2 RUNS the test suites, and postgresql check()
    # is `make check-world`, which includes the TAP tests that --enable-tap-tests
    # turns on. Without them that check fails and the package is lost, for a
    # reason that has nothing to do with the port.
    perl-io-tty perl-ipc-run
    # postgresql is expected to FAIL at stage 1, like clang and rust: it
    # configures --with-llvm for JIT, and building that against the host older
    # LLVM would either stop or, worse, not stop.
    postgresql
    # What ERPLibre Python dependencies need, and only what they need. Pillow
    # stops on `could not be found for jpeg, a required dependency` and pikepdf
    # on `qpdf/Constants.h: No such file or directory`. Odoo uses the first for
    # product images and the second to manipulate PDFs.
    #
    # MEASURED before reaching for the whole imaging stack: Pillow names jpeg
    # alone as required -- zlib it already has, and freetype only costs it
    # ImageFont, which nothing in Odoo calls. Arch freetype2 makedepends on
    # cairo, harfbuzz, librsvg and qt6-base for its demo programs, so that was
    # the difference between two packages and a dozen.
    libjpeg-turbo
    qpdf
    # openssh: not a dependency of anything here -- a DEPLOYMENT needs it. A
    # QEMU guest with no sshd can only be driven through its console, and the
    # s390x console is ttysclp0 over a single serial stream. FIDO2 is disabled
    # in the hook: it would cost libfido2, libcbor and hidapi for a USB token
    # this guest has no bus for.
    openssh
    # bc and cpio: the kernel build needs them, and nothing else here did.
    # bc computes kernel/timeconst.h; cpio packs the initramfs image.
    bc cpio
    # sudo, for the DEPLOYMENT and not for the build. The chroot refuses it a
    # hundred lines above, and that reasoning is sound where it stands: makepkg
    # wants sudo only for --syncdeps, which --nodeps replaces. It ends at the
    # target. ERPLibre install_arch_linux.sh is written as
    # `sudo pacman -S --needed`, and every Arch guide, hook and habit assumes
    # the binary exists; a machine that can only be administered by logging in
    # as root is not a deployment. Same argument that admitted openssh.
    sudo
    # base-devel, which stopped being a group in 2023 and is a meta package
    # now:  looks for a PACKAGE, and every Arch
    # installation guide -- ERPLibre own installer included -- asks for it by
    # that name. It compiles nothing; it names what a build machine needs, and
    # this port has all of it, sudo included, as of the line above.
    # debugedit, which base-devel names and makepkg calls to split debug
    # symbols. This port builds with !debug, so nothing here needs it -- a
    # machine that builds ITS OWN packages does.
    debugedit
    base-devel
    # cloud-init, and the closure it needs. Measured rather than guessed: the
    # PKGBUILDs were read by bash and the runtime dependencies followed until
    # nothing new appeared -- twenty-two names in four passes, plus the Python
    # packaging tools that none of them can be built without.
    #
    # WHY IT IS WANTED. A deployment can already set hostname, key and password
    # by writing into the image before first boot, which is enough for a plain
    # guest. cloud-init is what makes an image behave like every other cloud
    # image: a user-data of one's own, data sources, accounts created at boot.
    #
    # The order is the build order, not an alphabet: the packaging backends
    # first, because everything below them is built with them.
    python-flit-core python-installer python-packaging python-setuptools
    python-wheel python-build python-pathspec python-editables
    # calver and pluggy are BUILD dependencies of the two below, which is why
    # a closure computed from `depends` alone did not find them: trove-
    # classifiers stops on calver, hatchling on pluggy and trove-classifiers.
    python-calver python-pluggy
    # python-tomlkit is a RUNTIME dependency of hatchling, not a build one, so
    # neither a backend failure nor the build-order reasoning above pointed at
    # it: hatchling built, landed in the repository, and nothing could install
    # it. Only asking pacman to resolve the whole repository shows that kind of
    # hole -- a package comparison against the build list never will, the name
    # not being in the list to begin with.
    python-tomlkit
    python-trove-classifiers python-hatchling python-poetry-core
    # hatchling's plugins, which are not hatchling: a package whose version
    # comes from git needs hatch-vcs, and hatchling reports its absence as
    # `Unknown version source: vcs` rather than as a missing dependency.
    # attrs, urllib3 and referencing all stop there, on the same line.
    python-hatch-vcs python-hatch-fancy-pypi-readme
    # maturin, the backend that builds a Rust extension into a wheel, and the
    # two packages under it. Named without the python- prefix upstream, unlike
    # everything around it.
    #
    # THE CHAIN IS FOUR DEEP, and each link was found by building the one above
    # it: semantic-version, setuptools-rust, maturin, then rpds-py -- and
    # rpds-py is what jsonschema needs, which is what cloud-init needs. A
    # closure over `depends` shows none of it: every one of these is a BUILD
    # dependency, and they are only visible from the error of the build that
    # wanted them.
    python-semantic-version python-setuptools-rust maturin
    # The pure-Python leaves, then what depends on them.
    python-typing_extensions python-attrs python-idna python-urllib3
    python-certifi python-charset-normalizer python-requests
    # python-yaml, and NOT python-pyyaml: that is the name cloud-init depends
    # on, and the name Arch PROVIDES rather than the one it packages. Asking
    # for the provided name makes git ask for a login, which is how
    # gitlab.archlinux.org says a repository does not exist.
    # libyaml before python-yaml: the C library the binding loads at runtime.
    # It was missed for the same reason as the name above -- a closure looked
    # up python-pyyaml, which nothing packages, so nothing read what
    # python-yaml itself depends on.
    libyaml
    python-yaml python-configobj python-pyserial python-netifaces
    python-jsonpointer python-jsonpatch python-oauthlib
    # jsonschema's own chain. rpds-py is a Rust extension, which this port can
    # build: rust is already here, and pip compiled the same wheel for ERPLibre.
    python-rpds-py python-referencing python-jsonschema-specifications
    python-jsonschema
    # openbsd-netcat, which cloud-init calls, and the two libraries under it.
    libmd libbsd openbsd-netcat
    # A DHCP client: cloud-init names the virtual package, and something has to
    # provide it. dhcpcd rather than dhclient -- one binary, no ISC stack.
    dhcpcd
    # bash-completion: cloud-init's meson looks for it with pkg-config and
    # stops the configure when it is absent. It ships completion files, not
    # code, and is one of the two build dependencies cloud-init names.
    bash-completion
    cloud-init
    # growpart, which cloud-init needs to grow the root PARTITION before
    # it can grow the filesystem on it. cc_growpart knows three resizers
    # -- growpart, growfs and gpart -- and treats all three missing as
    # nothing to do: it logs one DEBUG line and returns. A guest then
    # comes up with the image's own size on a disk the deployment has
    # already enlarged, and no error says so anywhere. arch=any, a
    # /bin/sh script over sfdisk, partx and blkid.
    #
    # The RECIPE is named cloud-utils and splits into three; the hook
    # keeps only cloud-guest-utils, because cloud-image-utils names
    # cdrtools, qemu-img and wget, none of which this port builds.
    cloud-utils
    # THE CLOSURE STAGE 3 EXPOSED. Four packages that packages already here
    # DEPEND ON and that nothing ever built: stage 2 builds with --nodeps and
    # nothing checked afterwards, so clang, cython, linux-headers and
    # poetry-core each name something absent from the repository they live in.
    # Until these exist, `pacman -S clang` fails on a target, and a chroot
    # cannot be populated from repo2 alone -- which is how stage 3 found them.
    #
    # None was hard, which is the point: pahole wants libelf and zlib, lark
    # wants typing_extensions, pygments wants nothing, and compiler-rt is
    # llvm's own runtime library, built from the source llvm already uses.
    # They were missing for want of looking, not for want of a way.
    python-lark-parser python-pygments pahole compiler-rt
    # s390-tools, for zipl alone: the boot record an IPL reads. Its PKGBUILD is
    # written here rather than fetched -- Arch has no such package, this being
    # the one tool that exists only on this architecture. Without it a guest
    # boots a kernel handed to it from outside its own filesystem.
    s390-tools
    # linux: the kernel, and the reason a deployment needs one of our own. The
    # image in boot/ was cross-built in an earlier phase; it boots and mounts
    # ext4 over virtio-blk-ccw, and it has NO TCP/IP -- no PF_INET, no
    # /proc/sys/net/ipv4, and sshd dying on `Cannot bind any address`.
    # patches/pkgbuild/linux.sh generates an s390x config from the in-tree
    # defconfig and verifies sixteen symbols before the build proceeds.
    linux
    # Ce qu'exige l'installateur Arch d'ERPLibre, et dont l'absence le fait
    # sortir en erreur plutot que continuer en best-effort :
    #   less    le paginateur. git l'appelle pour log, diff, show et tag, et
    #           s'arrete sur « unable to execute pager » sans lui. pacman ne
    #           le tire pas : git ne le declare qu'en dependance optionnelle.
    #   nodejs  rtlcss et lessc, les preprocesseurs des feuilles de style
    #   npm     d'Odoo, tournent dessus. Son package() appelle jq, qui se lie
    #           a oniguruma.
    # « tk » n'est PAS ici : il ne donne a CPython que tkinter, qu'ERPLibre
    # importe derriere un except ModuleNotFoundError, et il tire la pile X11
    # entiere sur une machine sans ecran.
    # gtest : abseil-cpp le cherche en configuration et s'arrete sans lui, et
    # ninja le vendorise quand il ne le trouve pas. Le fournir une fois rend
    # les deux deterministes -- voir patches/pkgbuild/ninja.sh.
    gtest
    # abseil-cpp, ada, c-ares, libnghttp3, libngtcp2 et simdjson : les six
    # bibliotheques que nodejs attend du systeme et que le port n'avait pas.
    abseil-cpp ada c-ares libnghttp3 libngtcp2 simdjson
    less oniguruma jq nodejs npm
    # Ce que npm declare en dependances et que pacman refuse de resoudre sans :
    # node-gyp compile les extensions natives, nopt lit ses options, semver
    # compare les versions.
    semver nodejs-nopt node-gyp
    # onetbb : manifold3d refuse de configurer sans lui (« Parallel mode
    # enabled, but tbb was not found »). manifold3d vient de pythonopenscad,
    # lui-meme tire par to-3mf, que le module PLM de conversion CAO importe.
    # python-pip : la construction des liaisons Python d'onetbb l'appelle, et
    # s'arrete sur « No module named pip ». Le fournir garde le PKGBUILD
    # d'onetbb identique a celui d'Arch, la ou desactiver TBB4PY creerait une
    # divergence a porter.
    # libpciaccess et hwloc : onetbb declare hwloc, qui se lie a libpciaccess
    # pour enumerer la topologie materielle.
    libpciaccess hwloc onetbb
    # La grappe geospatiale : shapely se lie a geos, pyproj a proj, et proj a
    # libtiff, qui demande lui-meme jbigkit, libdeflate et libwebp. Les deux
    # modules Python sont des dependances declarees d'ERPLibre.
    geos jbigkit libdeflate libwebp libtiff proj giflib libpng
    # La grappe d'impression. pycups est importe par le module OCA
    # base_report_to_printer ET par odoo/addons/hw_drivers, les pilotes
    # d'imprimante d'Odoo lui-meme. avahi est une dependance DURE de libcups :
    # sans lui, dest.c reference des champs de struct que son propre #ifdef
    # n'a pas definis, et la compilation s'arrete.
    libdaemon glib2 avahi libpaper cups
    # L'userland qu'une image de deploiement doit porter, et que le portage
    # n'avait pas. nano et vim : le deploiement pose l'editeur de l'hote dans
    # l'invite (qemu_deploy.py, PKGS), et sans aucun des deux l'installation
    # s'arrete. procps-ng : ps, top, free. htop et libnl : le suivi
    # interactif, deja demande sur cette machine.
    nano vim procps-ng libnl htop
    # gpm : vim le declare pour la souris en console. Petit, et le fournir
    # evite une divergence de plus dans la recette de vim.
    # iproute2 : « ip », que cloud-init cherche pour choisir son renderer
    # reseau et dont l'absence le laissait sans aucun.
    gpm iproute2
)

# Packages a stage-1 run is EXPECTED to report as failed.
#
# Each one is a closure gap, not a defect: the recipe needs something the port
# builds itself and the host cannot supply -- our llvm, our libxml2 -- or a
# source that upstream withdrew. The reason for each is written beside the
# package in STAGE1_PACKAGES above; this list exists so the summary can
# separate them from a real regression, and so a reader comparing two runs can
# see at a glance whether the failures are the usual ones.
#
# A name belongs here only when the reason is permanent for stage 1. A package
# that fails because the host is missing a dependency it COULD have does not:
# that is a gap to close in install_host_packages, not an expectation to
# record. Removing a name is as meaningful as adding one -- it says stage 1
# now reaches further than it did.
STAGE1_EXPECTED_FAILURES=(
    clang       # needs llvm-gtest, which our llvm ships and the host has not
    lld         # same
    rust        # same, and depends on lld
    libxslt     # needs libxml2 >= 2.15.1; the host has an older one
    libaio      # upstream withdrew the release tarball
    postgresql  # configures --with-llvm against the host's older LLVM
    maturin     # Cargo.toml sets rust-version 1.89 and the distribution's
                # rustc is older; "rustc <version> is not supported by the
                # following packages". Stage 2 builds rust before it.
    python-rpds-py  # a maturin backend, so it waits on the same toolchain
)
