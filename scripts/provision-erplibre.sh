#!/usr/bin/env bash
# Install ERPLibre / Odoo 18 on a booted Arch s390x guest.
#
# Runs INSIDE the guest, as root, once it has network. Everything it needs from
# the distribution is already a package: gcc, git, postgresql, rust, python,
# libjpeg-turbo, qpdf. What it adds is the application.
#
# WHY pyenv AND NOT THE SYSTEM PYTHON. ERPLibre pins its interpreter --
# .python-odoo-version says 3.12.10 for Odoo 18 -- and this port carries 3.14
# for pacman and meson. Two interpreters, on purpose. pyenv COMPILES 3.12.10,
# which is why zlib, bzip2, xz, readline, sqlite, libffi and ncurses had to be
# in the image: they are not decoration, they are that build.
#
# WHY pip AND NOT poetry. poetry install stops on mysqlclient, a non-optional
# dependency in ERPLibre pyproject.toml that always compiles from source and
# always wants MariaDB client headers -- and mariadb-libs comes only from the
# whole mariadb pkgbase, which drags in boost, jemalloc, judy and cracklib and
# clones rocksdb, duckdb and columnstore. Hours of C++ for a MySQL client in a
# PostgreSQL application. Set aside deliberately; requirements are installed
# from the file ERPLibre generates, plus Odoo own, which is more complete.
set -euo pipefail

EL_HOME="${EL_HOME:-/opt/erplibre}"
EL_PY="${EL_PY:-3.12.10}"
EL_ODOO_BRANCH="${EL_ODOO_BRANCH:-18.0}"
EL_HTTP_PORT="${EL_HTTP_PORT:-8069}"
export GIT_TERMINAL_PROMPT=0

log() { printf '\n== %s ==\n' "$*"; }

log "PostgreSQL"
if [ ! -f /var/lib/postgres/data/PG_VERSION ]; then
    install -d -o postgres -g postgres /var/lib/postgres/data
    su -s /bin/sh postgres -c "initdb --locale=C.UTF-8 --encoding=UTF8 -D /var/lib/postgres/data"
fi
systemctl enable --now postgresql
for i in $(seq 1 30); do su -s /bin/sh postgres -c "psql -tAc 'select 1'" >/dev/null 2>&1 && break; sleep 2; done
su -s /bin/sh postgres -c "psql -tAc \"select 1 from pg_roles where rolname='odoo'\"" | grep -q 1 \
    || su -s /bin/sh postgres -c "createuser -s odoo"

log "CPython $EL_PY, compiled by pyenv"
export PYENV_ROOT=/opt/pyenv
[ -d "$PYENV_ROOT" ] || git clone -q --depth 1 https://github.com/pyenv/pyenv.git "$PYENV_ROOT"
export PATH="$PYENV_ROOT/bin:$PATH" MAKE_OPTS="-j$(nproc)"
pyenv install -s "$EL_PY"
PY="$PYENV_ROOT/versions/$EL_PY/bin/python3"
"$PY" -c "import sqlite3, ssl, zlib, bz2, lzma, ctypes, readline, curses; print('interpreter ok')"

log "ERPLibre and Odoo $EL_ODOO_BRANCH"
[ -d "$EL_HOME" ] || git clone -q --depth 50 -b develop https://github.com/ERPLibre/ERPLibre.git "$EL_HOME"
cd "$EL_HOME"
mkdir -p "odoo$EL_ODOO_BRANCH"
[ -d "odoo$EL_ODOO_BRANCH/odoo" ] || git clone -q --depth 1 -b "$EL_ODOO_BRANCH" \
    https://github.com/odoo/odoo.git "odoo$EL_ODOO_BRANCH/odoo"
# pyproject.toml and poetry.lock are GENERATED, and gitignored: the template
# lives in requirement/ and is selected by the Odoo/Python pair.
cp "requirement/pyproject.odoo${EL_ODOO_BRANCH}_python${EL_PY}.toml" pyproject.toml
cp "requirement/poetry.odoo${EL_ODOO_BRANCH}_python${EL_PY}.lock" poetry.lock

log "Python dependencies"
[ -d .venv ] || "$PY" -m venv .venv
V="$EL_HOME/.venv/bin"
"$V/pip" install -q --upgrade pip setuptools wheel
grep -viE '^mysqlclient' "requirement/requirements.odoo${EL_ODOO_BRANCH}_python${EL_PY}.txt" > /tmp/req.txt
"$V/pip" install -q -r /tmp/req.txt || true
"$V/pip" install -q -r "odoo$EL_ODOO_BRANCH/odoo/requirements.txt"

log "Odoo database"
cd "$EL_HOME/odoo$EL_ODOO_BRANCH/odoo"
su -s /bin/sh postgres -c "psql -tAlq" | cut -d\| -f1 | grep -qx odoo_erplibre \
    || "$V/python" odoo-bin -d odoo_erplibre --db_user=odoo -i base \
         --without-demo=all --stop-after-init --log-level=warn

log "Service"
cat > /etc/systemd/system/odoo.service <<UNIT
[Unit]
Description=Odoo 18 (ERPLibre)
After=postgresql.service
Requires=postgresql.service

[Service]
ExecStart=$V/python $EL_HOME/odoo$EL_ODOO_BRANCH/odoo/odoo-bin -d odoo_erplibre --db_user=odoo --http-port=$EL_HTTP_PORT --log-level=warn
WorkingDirectory=$EL_HOME/odoo$EL_ODOO_BRANCH/odoo
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now odoo.service

log "Verification"
for i in $(seq 1 40); do
    code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$EL_HTTP_PORT/web/login" || true)
    [ "$code" = "200" ] && break
    sleep 5
done
printf '  /web/login -> %s\n' "${code:-aucune reponse}"
[ "${code:-}" = "200" ] || { echo "ERPLibre did not answer" >&2; exit 1; }
echo "  ERPLibre is serving on port $EL_HTTP_PORT"
