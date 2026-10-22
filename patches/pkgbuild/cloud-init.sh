#!/usr/bin/env bash
# cloud-init: rendre cloud.cfg pour Arch, pas pour la machine qui construit.
#
# LA PANNE. Le paquet livre /etc/cloud/cloud.cfg avec
#
#   # Unknown/fallback distro.
#   distro: ubuntu
#
# cloud-init instancie donc la classe Distro d'Ubuntu sur un Arch, et deux
# modules s'arretent au premier amorcage :
#
#   keyboard  « systemctl restart console-setup » -- unite inexistante
#   locale    installe le paquet Debian « locales »
#
# LA CAUSE. meson.build rend config/cloud.cfg.tmpl par tools/render-template,
# dont --variant vaut par defaut util.system_info()["variant"] : la variante
# de la MACHINE QUI CONSTRUIT, jamais celle du paquet.
#
# Et dans un chroot de construction, cette variante ne vaut pas « arch », ni
# meme le nom de la distribution hote. get_linux_distro() ne lit QUE
# /etc/os-release ; le paquet filesystem n'installe que /usr/lib/os-release, et
# le lien /etc/os-release est pose par systemd-tmpfiles au premier amorcage, ce
# qu'un chroot ne fait jamais. La fonction previent -- « Unable to determine
# distribution, template expansion may have unexpected results » -- et rend un
# nom de distribution VIDE, que _get_variant() fait retomber sur « linux ». Le
# gabarit n'a pas de branche « linux » : il prend sa branche par defaut, qui
# fixe distro a ubuntu. Il livre le signe deux fois de plus : la ou la variante
# n'est dans aucune table, la branche « else » de cloud.cfg.tmpl recopie son
# nom tel quel, d'ou « name: linux » et « gecos: linux Cloud User ».
#
# L'AVERTISSEMENT NE DISPARAIT PAS. render-template appelle system_info() pour
# calculer la valeur par defaut de --variant, donc avant de lire ses arguments :
# les cinq « Unable to determine distribution » restent au journal, option ou
# non. Ce qui se verifie est le fichier rendu, pas le journal :
#
#   grep 'distro:' build/cloud.cfg   -> distro: arch
#
# CE QUE LA VARIANTE ARCH CHANGE, mesure en rendant le gabarit deux fois :
# distro passe a arch, default_user prend name arch, lock_passwd et groups
# [wheel, users], paths declare cloud_dir et templates_dir, et ssh_svcname vaut
# sshd. Le reste du fichier est identique au caractere pres.
#
# UN SEUL ARTEFACT EST EN JEU. meson.build appelle render-template cinq fois :
# le generateur systemd, trois unites, et cloud.cfg. Rendues en « arch » puis
# en « linux », les quatre premieres sortent octet pour octet identiques --
# aucune de leurs branches ne separe ces deux variantes. Leur passer l'option
# ne changerait donc rien ; seule la cible qui differe est touchee, pour que le
# correctif montre de lui-meme ou est le defaut.
#
# POURQUOI L'EDITION VIT DANS prepare(). Un crochet tourne a cote du PKGBUILD,
# avant que makepkg n'ait rien extrait : meson.build n'existe pas encore. Ce
# qu'un crochet peut faire est poser l'edition la ou les sources seront. Meme
# raison, et meme forme, que patches/pkgbuild/compiler-rt.sh.
#
# PAS D'OPTION MESON POUR CELA : meson_options.txt n'expose ni variant ni
# distro. L'option appartient a render-template, et la cible meson est le seul
# endroit d'ou on peut la lui passer.
#
# A FERMER EN AMONT. Un paquet dont le contenu depend de la distribution de la
# machine qui le batit n'est reproductible nulle part ; Arch ne le voit pas
# parce qu'Arch batit sur Arch. Poser un /etc/os-release dans le chroot
# corrigerait ce paquet-ci, mais laisserait son contenu suspendu a
# l'environnement : la reponse est l'option, pas le chroot.
set -euo pipefail
python3 - <<'ZZPY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()
# La recette n'a pas de prepare(). En ajouter un second a cote de celui que
# l'amont ecrirait un jour serait muet : bash ne garde que la derniere
# definition, et l'une des deux editions disparaitrait sans un mot.
assert "\nprepare()" not in s, "cloud-init: la recette a deja un prepare()"
anchor = "\nbuild() {\n"
assert s.count(anchor) == 1, "cloud-init: la ligne `build() {` n est pas unique"
fix = r'''
prepare() {
  cd $pkgname-$pkgver
  # --variant vaut par defaut la variante de la machine qui construit, et un
  # chroot de construction n'y rend pas « arch » : sans cette option cloud.cfg
  # sort en « distro: ubuntu ». Voir patches/pkgbuild/cloud-init.sh.
  #
  # Le compte precede la substitution : si l'amont reecrit cette cible, mieux
  # vaut s'arreter ici que livrer un cloud.cfg qui nomme la mauvaise distro.
  [ "$(grep -c "'--is-yaml', '@INPUT@'," meson.build)" = 1 ] || {
    echo "cloud-init: la cible cloud.cfg de meson.build a change" >&2; exit 1; }
  # [[:blank:]] et non \s : \s n'est pas reconnu dans une classe de caracteres.
  sed -i "s|^\([[:blank:]]*\)'--is-yaml', '@INPUT@',|\1'--variant', 'arch',\n\1'--is-yaml', '@INPUT@',|" meson.build
  grep -q "'--variant', 'arch'," meson.build || {
    echo "cloud-init: la variante arch n a pas ete posee" >&2; exit 1; }
}

build() {
'''
s = s.replace(anchor, fix, 1)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY
# Les garde-fous visent des COMMANDES ancrees en debut de ligne, et non les
# chaines qu'elles portent : les commentaires poses juste au-dessus nomment la
# meme option, et un grep de « --variant » seul se declencherait sur son
# propre remplacement.
[ "$(grep -c -E '^prepare\(\) \{$' PKGBUILD)" = 1 ] || {
    echo "cloud-init: prepare() n est pas defini exactement une fois" >&2; exit 1; }
grep -qE "^[[:blank:]]*sed -i .*'--variant', 'arch',.*meson\.build\$" PKGBUILD || {
    echo "cloud-init: la substitution de la variante n a pas ete posee" >&2; exit 1; }
grep -qE "^[[:blank:]]*grep -q \"'--variant', 'arch',\" meson\.build" PKGBUILD || {
    echo "cloud-init: prepare() ne verifie plus son propre travail" >&2; exit 1; }
# build() configure toujours meson, et package() installe toujours ce qu'il a
# bati : sans eux le paquet sortirait vide sans erreur.
grep -qE '^[[:blank:]]*arch-meson \$pkgname-\$pkgver build$' PKGBUILD || {
    echo "cloud-init: build() ne configure plus meson" >&2; exit 1; }
grep -qE '^[[:blank:]]*meson install -C build --destdir "\$pkgdir"$' PKGBUILD || {
    echo "cloud-init: package() n installe plus la construction" >&2; exit 1; }
echo "cloud-init: cloud.cfg rendu en variante arch (distro: arch, ssh_svcname: sshd)"