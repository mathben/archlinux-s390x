#!/bin/sh
# L'interface Tcl de vim ne compile pas contre Tcl 9.
#
# src/if_tcl.c declare ses prototypes avec _ANSI_ARGS_, une macro que Tcl 8
# definissait dans tcl.h et que Tcl 9 a retiree. Le compilateur s'arrete sur
# « expected '=', ',', ';', 'asm' or '__attribute__' before '_ANSI_ARGS_' »,
# repete pour chaque prototype du fichier. Ce n'est pas propre a s390x : tout
# vim 9.x bati contre Tcl 9 tombe dessus.
#
# Le portage porte Tcl 9.0.1 parce que c'est ce qu'Arch distribue ; Arch, lui,
# ne rencontre pas la panne parce que son paquet vim est bati contre le tcl
# de ses propres depots au moment ou les deux versions s'accordaient.
#
# Ce qui se perd : « :tcl » et les greffons ecrits en Tcl. Les interfaces
# Python, Perl, Lua et Ruby ne sont pas touchees. Pour un editeur pose dans
# une VM parce que le deploiement y copie l'editeur de l'hote, c'est sans
# consequence.
#
# LA SECONDE PANNE, une fois Tcl ecarte : « configure: error: could not
# configure X ». La recette batit DEUX binaires, vim et gvim, et le second
# demande X11 et GTK3 -- « --with-x=yes --enable-gui=gtk3 ». Le portage n'a
# ni l'un ni l'autre, et une machine sans ecran n'a que faire d'un editeur
# graphique. Le bloc gvim est donc retire du build(), et gvim de pkgname :
# l'y laisser ferait reclamer a makepkg un paquet que plus rien ne produit.
# vim et vim-runtime restent.
python3 - <<'ZZPY'
import io, re, sys
s = io.open("PKGBUILD", encoding="utf-8").read()
motif = re.compile(r"^([ \t]*)--enable-tclinterp=dynamic[ \t]*\\?[ \t]*$", re.M)
n = len(motif.findall(s))
if n == 0:
    sys.exit("vim: --enable-tclinterp introuvable, recette inattendue")
# Les deux variantes du paquet (vim et gvim) portent la meme option : les
# deux doivent tomber, sinon l'une des deux echoue encore.
s = motif.sub(lambda m: m.group(1) + "--disable-tclinterp \\", s)
# Le sous-shell « (cd gvim ... ) » du build(), et le msg2 qui l'annonce.
m = re.search(r'\n[ \t]*msg2 "Building gvim\.\.\."\n[ \t]*\(cd gvim\n.*?\n[ \t]*\)\n',
              s, re.S)
if not m:
    sys.exit("vim: le bloc de construction gvim est introuvable")
s = s[:m.start()] + "\n" + s[m.end():]

# pkgname est un tableau sur UNE ligne : « pkgname=('vim' 'gvim'
# 'vim-runtime') ». Retirer la seule entree gvim, sans toucher aux deux
# autres ni a la forme de la ligne.
m2 = re.search(r"^pkgname=\((.*)\)[ \t]*$", s, re.M)
if not m2:
    sys.exit("vim: pkgname n'a pas la forme attendue")
noms = [x for x in m2.group(1).split() if x.strip("'\"") != "gvim"]
if len(noms) != len(m2.group(1).split()) - 1:
    sys.exit("vim: gvim absent de pkgname")
s = s[:m2.start()] + "pkgname=(" + " ".join(noms) + ")" + s[m2.end():]
m3 = re.search(r"^package_gvim\(\) \{.*?^\}\n", s, re.S | re.M)
if not m3:
    sys.exit("vim: package_gvim() introuvable")
s = s[:m3.start()] + s[m3.end():]

io.open("PKGBUILD", "w", encoding="utf-8").write(s)
print("  vim: %d tclinterp desactive(s), gvim retire" % n)
ZZPY

# Le motif vise une OPTION en debut de ligne, pas la chaine « tclinterp » :
# les commentaires ci-dessus la portent, et un grep nu s'y declencherait.
grep -qE '^[[:space:]]*--enable-tclinterp' PKGBUILD && {
    echo "vim: une option --enable-tclinterp subsiste" >&2; exit 1; }
grep -qE '^[[:space:]]*--disable-tclinterp' PKGBUILD || {
    echo "vim: --disable-tclinterp n a pas ete pose" >&2; exit 1; }
# Les autres interfaces doivent survivre : si configure ne les voyait plus,
# le paquet sortirait ampute sans que rien ne le signale.
grep -qE '^[[:space:]]*--enable-python3interp' PKGBUILD || {
    echo "vim: l interface Python a disparu" >&2; exit 1; }
# Le motif vise la DECLARATION, ancree, pas la chaine « gvim » : les
# commentaires ci-dessus la portent, et le chemin source gvim/ demeure.
grep -qE "^[[:space:]]*'?gvim'?[[:space:]]*$" PKGBUILD && {
    echo "vim: gvim subsiste dans pkgname" >&2; exit 1; }
grep -qE '^package_gvim\(\)' PKGBUILD && {
    echo "vim: package_gvim() subsiste" >&2; exit 1; }
grep -qE '^package_vim\(\)' PKGBUILD || {
    echo "vim: package_vim() a disparu" >&2; exit 1; }
grep -qE '\-\-with-x=yes' PKGBUILD && {
    echo "vim: une configuration X subsiste" >&2; exit 1; }
echo "vim: interface Tcl desactivee, les autres intactes"
