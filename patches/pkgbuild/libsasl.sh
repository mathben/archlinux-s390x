#!/usr/bin/env bash
# libsasl: --enable-sql, and the message names a file that exists.
#
#   sql.c:192:10: fatal error: libpq-fe.h: No such file or directory
#
# THE TRAP: the header is there.
#
#   /usr/include/postgresql/libpq-fe.h
#
# Debian and Ubuntu put the PostgreSQL client headers in a subdirectory, and
# the PKGBUILD passes --with-pgsql=/usr/lib, which sends configure looking
# somewhere else. "No such file or directory" is true of the path it tried and
# false of the file, so the obvious move -- install libpq-dev -- changes
# nothing, because it is already installed.
#
# AND IT IS A QUEUE, WHICH IS THE REAL POINT. The same PKGBUILD passes
# --with-mysql=/usr, and mysql.h is at /usr/include/mariadb/mysql.h -- another
# subdirectory, another header that exists and cannot be found. Fixing the
# first uncovers the second. This port already wrote the rule down, in
# install_host_deps, after dbus asked for three documentation tools in a row:
# a single missing library is a host dependency; a queue of them is a feature
# that should be disabled.
#
# So the SQL auxprop plugin goes, along with the three --with-*sql flags that
# feed it. What it costs is worth stating precisely, because it is nothing:
# Arch itself declares depends=(glibc) for this package and says why in a
# comment at the top of its own PKGBUILD -- "else this would require mariadb
# and postgresql in [core]". The plugins are dlopened, never linked, so
# dropping them removes no dependency Arch was tracking and no capability
# anything in this port uses. libsasl is here because libldap wants SASL
# authentication; that is the DIGEST/GSSAPI/PLAIN side, all still enabled.
#
# Deferred, not architectural: a server that wants SQL auxprop rebuilds this
# with the include paths supplied. TODO.md records it.
set -euo pipefail
python3 - <<'PY'
import io, re
s = io.open("PKGBUILD", encoding="utf-8").read()

old = "    --enable-sql\n"
assert s.count(old) == 1, "libsasl: expected exactly one --enable-sql"
s = s.replace(old, "    --disable-sql\n", 1)

# The three database locations exist only to serve the plugin just disabled.
n = 0
for flag in ("--with-mysql=", "--with-pgsql=", "--with-sqlite3="):
    pat = re.compile(r"^\s*" + re.escape(flag) + r".*\n", re.M)
    found = pat.findall(s)
    assert len(found) == 1, "libsasl: expected one %s line, found %d" % (flag, len(found))
    s = pat.sub("", s, count=1)
    n += 1
assert n == 3
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
PY
grep -q -- '--disable-sql' PKGBUILD || {
    echo "libsasl: sql plugin still enabled" >&2; exit 1; }
for f in -- '--with-mysql' '--with-pgsql' '--with-sqlite3'; do
    [ "$f" = "--" ] && continue
    grep -qF -- "$f" PKGBUILD && {
        echo "libsasl: $f survived" >&2; exit 1; }
done
grep -q -- '--enable-gssapi' PKGBUILD || {
    echo "libsasl: gssapi lost -- libldap needs SASL auth" >&2; exit 1; }
echo "libsasl: SQL auxprop disabled (two headers that exist, on paths it does not try)"
