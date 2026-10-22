#!/bin/sh
# iproute2 declare trois dependances que le portage ne peut pas satisfaire :
# libxtables.so (paquet iptables, qui tire six paquets netfilter) et
# libbpf / libbpf.so.
#
# Son configure ne les EXIGE pas : la recette l'appelle avec « --color auto »
# et rien d'autre, et configure detecte ces bibliotheques puis s'en passe
# quand elles manquent. Le binaire se batit donc sans elles ; ce qui se perd
# est le filtrage « tc » par xtables et le chargement de programmes BPF.
# « ip », « ss » et « bridge » sont entiers.
#
# Ne retirer que la DECLARATION serait un mensonge si la bibliotheque etait
# presente dans le chroot : le binaire s'y lierait et le paquet ne le dirait
# plus. Elle ne l'est pas -- ni iptables ni libbpf ne sont dans le depot --
# et le controle SONAME de test-chroot.sh verifie de toute facon que chaque
# soname demande par un binaire a un fournisseur.
python3 - <<'ZZPY'
import io, re, sys
lignes = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
deb = next((i for i, l in enumerate(lignes) if l.startswith("depends=(")), None)
if deb is None:
    sys.exit("iproute2: depends introuvable")
fin = next((i for i in range(deb, len(lignes)) if ")" in lignes[i].split("#")[0]), None)
if fin is None:
    sys.exit("iproute2: depends n'est pas refermee")

# Le bloc porte des commentaires EN LIGNE (« # from iptables or
# iptables-legacy ») : les couper avant de lire les noms, sinon le « # »
# commente la parenthese fermante et le PKGBUILD ne parse plus.
noms = []
for i in range(deb, fin + 1):
    code = lignes[i].split("#")[0]
    code = code.replace("depends=(", " ").replace(")", " ")
    noms += [x.strip("'\"") for x in code.split() if x.strip("'\"")]

retirer = {"libxtables.so", "libbpf", "libbpf.so"}
absentes = retirer - set(noms)
if absentes:
    sys.exit("iproute2: absentes de depends: %s" % ", ".join(sorted(absentes)))
garde = [n for n in noms if n not in retirer]
if not garde:
    sys.exit("iproute2: depends serait vide")

lignes[deb:fin + 1] = ["depends=(" + " ".join("'%s'" % n for n in garde) + ")"]
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lignes))
print("  iproute2: %d retirees, %d gardees (%s)"
      % (len(noms) - len(garde), len(garde), " ".join(garde)))
ZZPY

# Le motif vise la LIGNE depends, pas la chaine : les commentaires ci-dessus
# nomment les trois dependances et un grep nu s'y declencherait.
grep -qE '^depends=\(.*libbpf' PKGBUILD && {
    echo "iproute2: libbpf subsiste dans depends" >&2; exit 1; }
grep -qE '^depends=\(.*libxtables' PKGBUILD && {
    echo "iproute2: libxtables subsiste dans depends" >&2; exit 1; }
grep -qE '^depends=\(.*glibc' PKGBUILD || {
    echo "iproute2: depends a ete vide, ce n est pas voulu" >&2; exit 1; }
echo "iproute2: xtables et bpf retires des dependances"
