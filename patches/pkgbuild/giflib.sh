#!/bin/sh
# « make » nu construit la bibliothèque ET la documentation HTML, et celle-ci
# passe par xmlto, docbook-xsl et imagemagick — une chaîne d'outils de
# documentation que le portage n'a pas. La construction s'arrête sur
# « xmlto: No such file or directory » alors que libgif.so est déjà liée.
#
# « make libgif.so » s'en tient à la bibliothèque. Ce qui se perd est le
# répertoire doc/ du paquet : les pages de manuel et les HTML. Ce qui reste
# est ce dont libwebp-utils et libtiff ont besoin, c'est-à-dire la
# bibliothèque et ses en-têtes.
python3 - <<'ZZPY'
import io, re, sys
s = io.open("PKGBUILD", encoding="utf-8").read()
m = re.search(r'^build\(\) \{\n(.*?)^\}', s, re.S | re.M)
if not m:
    sys.exit("giflib: build() introuvable")
corps = m.group(1)
if not re.search(r'^[ \t]*make[ \t]*$', corps, re.M):
    sys.exit("giflib: build() n'appelle plus « make » nu")
neuf = re.sub(r'^([ \t]*)make[ \t]*$',
              r'\1# La doc HTML demande xmlto, docbook-xsl et imagemagick.\n'
              r'\1make libgif.so libgif.a',
              corps, count=1, flags=re.M)
s = s.replace(corps, neuf, 1)

# package() appelle « make install », cible agregee qui comprend install-doc
# et rappelle donc xmlto. Les cibles install-lib et install-include posent la
# bibliotheque et ses en-tetes ; install-bin, install-man et install-doc sont
# ecartees avec la documentation.
m2 = re.search(r'^(\s*)make PREFIX=/usr DESTDIR="\$\{pkgdir\}" install$',
               s, re.M)
if not m2:
    sys.exit("giflib: l'appel « make ... install » de package() a change")
s = s[:m2.start()] + (
    m2.group(1) + '# « install » entraine install-doc, donc xmlto.\n' +
    m2.group(1) + 'make PREFIX=/usr DESTDIR="${pkgdir}" install-lib install-include'
) + s[m2.end():]

io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY

grep -qE '^[[:space:]]*make libgif\.so libgif\.a[[:space:]]*$' PKGBUILD || {
    echo "giflib: la cible restreinte n a pas ete posee" >&2; exit 1; }
# package() doit continuer d'installer : une cible mal choisie donnerait un
# paquet vide, que rien d'autre ne signalerait.
grep -qE 'make PREFIX=/usr DESTDIR="\$\{pkgdir\}" install-lib install-include' PKGBUILD || {
    echo "giflib: package() n installe plus la bibliotheque" >&2; exit 1; }
echo "giflib: bibliotheque seule, documentation HTML ecartee"
