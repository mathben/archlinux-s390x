#!/bin/sh
# Deux options que la recette force et que le portage ne peut pas satisfaire.
#
# introspection : meson cherche g-ir-scanner, fourni par gobject-introspection,
# qui se batit CONTRE glib2. Aucun des deux ne peut naitre le premier tant que
# l'option est exigee. C'est le cycle d'amorcage connu de glib2 ; Arch le
# resout avec un glib2 intermediaire, le portage en se passant des .gir.
#
# sysprof : le profileur attend libsysprof-capture, qu'Arch ne publie pas sous
# ce nom — le clone se heurte a une demande d'identifiants, c'est-a-dire a un
# depot absent.
#
# man-pages et documentation : rst2man vient de python-docutils, gi-docgen
# de l'introspection qu'on vient de couper. Tous deux ne produisent que de
# la documentation.
#
# Ce qui se perd est la description introspectable de GLib, utile a
# python-gobject et aux liaisons dynamiques, les points de mesure du
# profileur, et les pages de manuel. Ce dont avahi puis cups ont besoin est la bibliotheque C, que ces
# deux options ne touchent pas.
python3 - <<'ZZPY'
import io, re, sys
s = io.open("PKGBUILD", encoding="utf-8").read()
chg = []
for opt in ("sysprof", "introspection", "man-pages"):
    motif = re.compile(r"^(\s*-D %s=)enabled\s*$" % opt, re.M)
    s, n = motif.subn(r"\1disabled", s)
    if n:
        chg.append("%s (%d)" % (opt, n))
# documentation=true est un booleen, pas une feature : il n'a pas de
# « disabled ». Il entraine gi-docgen, qui demande l'introspection qu'on
# vient de couper.
motif = re.compile(r"^(\s*-D documentation=)true\s*$", re.M)
s, n = motif.subn(r"\1false", s)
if n:
    chg.append("documentation (%d)" % n)
if "-D introspection=" not in s:
    # L'option n'etait pas listee : meson la met a auto, et la detection
    # echoue en erreur plutot qu'en repli. L'ajouter explicitement.
    m = re.search(r"^(\s*)-D sysprof=disabled\s*$", s, re.M)
    if not m:
        sys.exit("glib2: impossible de placer -D introspection=disabled")
    s = s[:m.end()] + "\n" + m.group(1) + "-D introspection=disabled" + s[m.end():]
    chg.append("introspection (ajoutee)")
if not chg:
    sys.exit("glib2: aucune des deux options n'a ete trouvee")
# package_glib2() deplace usr/share/doc vers le sous-paquet glib2-docs par
# _pick, qui echoue sur un repertoire absent. La documentation etant coupee,
# il n'existe plus. Le retrait de cette ligne laisse glib2-docs vide, ce qui
# est exact : il n'y a plus de documentation a y mettre.
# _pick deplace des chemins vers les sous-paquets et s'arrete sur un chemin
# absent. Sans documentation ni pages de manuel, plusieurs de ces chemins
# n'existent plus : usr/share/doc, les .1 de gdbus-codegen, glib-mkenums,
# glib-genmarshal et gresource. Les enumerer un a un les ferait reapparaitre
# a la moindre evolution de la recette ; rendre _pick tolerant couvre le cas
# general et ne change rien quand le chemin existe.
m = re.search(r"^(\s*)mv \"\$f\" \"\$d\"\s*$", s, re.M)
if not m:
    sys.exit("glib2: le corps de _pick a change")
s = (s[:m.start()]
     + m.group(1) + "# Un chemin absent n'est pas une erreur : la doc et les\n"
     + m.group(1) + "# pages de manuel ne sont pas produites ici.\n"
     + m.group(1) + '[ -e "$f" ] || continue\n'
     + m.group(1) + 'mv "$f" "$d"'
     + s[m.end():])
chg.append("_pick tolerant")

# Desactiver l'option ne suffit pas : libsysprof-capture reste declare en
# dependance, et pacman refuse alors d'installer glib2 — puis tout ce qui en
# depend. Le paquet n'existe pas chez Arch sous ce nom, et sans -D sysprof la
# bibliotheque ne s'y lie plus.
m5 = re.search(r"^\s*libsysprof-capture\s*$\n", s, re.M)
if not m5:
    sys.exit("glib2: libsysprof-capture absent de depends")
s = s[:m5.start()] + s[m5.end():]
chg.append("libsysprof-capture retire des depends")

io.open("PKGBUILD", "w", encoding="utf-8").write(s)
print("  glib2: " + ", ".join(chg))
ZZPY

grep -qE '^\s*-D sysprof=disabled\s*$' PKGBUILD || {
    echo "glib2: sysprof n est pas desactive" >&2; exit 1; }
grep -qE '^\s*-D introspection=disabled\s*$' PKGBUILD || {
    echo "glib2: introspection n est pas desactivee" >&2; exit 1; }
grep -qE '^\s*-D man-pages=disabled\s*$' PKGBUILD || {
    echo "glib2: les pages de manuel ne sont pas desactivees" >&2; exit 1; }
grep -qE '^\s*-D documentation=false\s*$' PKGBUILD || {
    echo "glib2: la documentation n est pas desactivee" >&2; exit 1; }
grep -qE '^\s*\[ -e "\$f" \] \|\| continue\s*$' PKGBUILD || {
    echo "glib2: _pick n est pas tolerant a un chemin absent" >&2; exit 1; }
grep -qE '^\s*libsysprof-capture\s*$' PKGBUILD && {
    echo "glib2: libsysprof-capture subsiste dans depends" >&2; exit 1; }
grep -qE '^\s*-D ' PKGBUILD || {
    echo "glib2: les options meson ont disparu" >&2; exit 1; }
echo "glib2: introspection et sysprof desactives, bibliotheque C inchangee"
