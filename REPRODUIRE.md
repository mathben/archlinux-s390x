# Refaire le portage, de l'étage 1 à la VM déployée, à la main

Ce document est une PROCÉDURE, pas une description. Chaque commande y figure
telle qu'elle a été lancée, et chaque vérification telle qu'elle a répondu.

## Ce qu'il garantit, et ce qu'il ne garantit pas

**Garanti** : les étapes marquées « vérifié » ont tourné sur un hôte neuf, et
la sortie citée est celle qui a été obtenue. Une étape non marquée n'a pas été
exécutée telle quelle, et vous êtes le premier à l'éprouver.

**Non garanti** : que le résultat soit identique au précédent. L'étage 1 bâtit
avec la chaîne de l'HÔTE ; changez d'Ubuntu, vous obtenez un autre étage 1.
C'est la mécanique, pas un défaut — l'étage 2 existe pour effacer cette trace.

**Pourquoi ce fichier existe** : `TODO.md` a longtemps affirmé que des liens
pontaient les en-têtes multiarch. Aucun script ne les créait. Un document qui
décrit une étape que personne n'exécute coûte plus cher qu'un silence. Tout
ce qui suit est donc soit exécuté, soit annoncé comme non exécuté.

## 0. La machine

Une VM s390x sous Ubuntu, 12 cœurs, **150 Go de disque**. L'arbre de
construction de rust atteint 19 Go à lui seul ; en dessous de 100 Go la passe
s'arrête au milieu et laisse un état qu'il faut démêler à la main.

Vérifié sur Ubuntu 25.10, noyau 6.17. L'étage 1 d'origine avait été bâti sur
24.04 : les deux marchent, ils ne donnent pas le même étage 1.

## 1. L'hôte

```bash
git clone <dépôt> ~/git/archlinux-s390x
cd ~/git/archlinux-s390x
bash scripts/bootstrap-pacman.sh
```

Ce script, et lui seul, a le droit de modifier l'hôte. Il installe une
soixantaine de paquets `-dev`, bâtit `pacman` depuis les sources dans
`/usr/local/bin`, rafraîchit le cache du lieur, écrit `CHOST`, `MAKEFLAGS` et
`SRCDEST` dans `/etc/makepkg.conf`, et pose les ponts d'en-têtes multiarch.

**Vérifié.** Il se termine sur :

```
== Done ==
/usr/local/bin/pacman
/usr/local/bin/makepkg
/usr/local/bin/repo-add
```

Contrôlez avant d'aller plus loin — chacune de ces trois lignes a déjà manqué :

```bash
pacman --version                      # 7.1.0, et non celui d'Ubuntu
grep -E '^(CHOST|SRCDEST)=' /etc/makepkg.conf
ls -l /usr/include/asm /usr/include/sys/sdt-config.h
```

`CHOST` doit être `s390x-ibm-linux-gnu`, le triplet canonique. Celui d'Ubuntu,
`s390x-linux-gnu`, fait échouer gcc sur son propre empaquetage.

## 2. Étage 1 — 228 paquets

```bash
EL_NOCHECK=1 bash scripts/build-stage1.sh > ~/work/arch-s390x/etage1.log 2>&1
```

Des heures. Suivre depuis un autre terminal :

```bash
L=~/work/arch-s390x/etage1.log
grep -cE '^OK ' $L ; grep -E '^FAIL ' $L
```

Les paquets produits vont dans `~/work/arch-s390x/repo/s390x`, les archives
sources dans `~/work/arch-s390x/pkg/.sources` — ce second répertoire est le
miroir local, et il est la seule protection contre un amont qui disparaît.
`libaio` a déjà disparu du sien.

Reprendre après un arrêt : relancer la même commande. Les paquets déjà bâtis
sont sautés. Pour en forcer un, le NOMMER — ne jamais éditer le registre
d'état, qui est la mémoire du portage :

```bash
bash scripts/build-stage1.sh gcc        # un nom passe avant le registre
```

### Les backends python que la distribution n'a pas

L'étage 1 compile avec l'interpréteur de l'hôte. Une recette qui réclame un
backend absent s'arrête avant de compiler quoi que ce soit, sur une ligne qui
ne dit pas d'où vient le manque :

```
ERROR Missing dependencies: calver
```

Deux sources y répondent, et l'ordre compte. **D'abord apt**, qui entretient
ce qu'il livre : la liste est dans `install_host_packages`. **Ensuite le
portage lui-même**, pour ce qu'apt n'a pas — un paquet bâti range son module
en disposition Debian dans son archive, et `HOST_PYTHON_MODULES` le fait
extraire vers `/usr/local/lib/pythonX.Y/dist-packages` dès qu'il est bâti.
Ajouter un nom à cette liste suffit ; l'ordre de `STAGE1_PACKAGES` place déjà
le fournisseur avant ses consommateurs.

Un greffon est un paquet à part : réclamer `hatchling` n'apporte ni
`hatch-vcs` ni `hatch-fancy-pypi-readme`.

## 3. Étage 2

```bash
EL_NOCHECK=1 bash scripts/build-stage2.sh --all
```

Peuple un chroot depuis l'étage 1 puis rebâtit tout avec la chaîne ainsi
obtenue. Sortie dans `repo2/s390x`. Se termine par une épreuve RESOLVE qui
demande à pacman si le dépôt entier s'installe d'un bloc.

### Avant de toucher à `CHROOT_PKGS` : l'ensemble doit RÉSOUDRE

Le chroot se peuple depuis repo1. Qu'un nom y existe ne suffit pas — ses
dépendances doivent y être aussi, sinon `make_rootfs` s'arrête et l'étage 2
ne démarre pas du tout :

```
warning: cannot resolve "libxslt", a dependency of "docbook-xsl"
stage2: populate failed
```

`libxslt` est un des paquets que l'étage 1 ne peut PAS bâtir. Ajouter
`docbook-xsl`, qui en dépend, suffit à tout bloquer. Le contrôle se fait avant,
sur l'ensemble entier, avec la configuration pacman de la section 4 bis :

```bash
sudo pacman --config /tmp/r.conf --dbpath /tmp/r.db -Sp <tous les noms>
```

### UNE PASSE NE SUFFIT PAS, et ce n'est pas un défaut

Le chroot s'enrichit à mesure que la liste avance : un paquet bâti y est
installé, et devient disponible pour les suivants. Une recette qui réclame un
outil placé APRÈS elle dans la liste échoue donc, puis passe au tour suivant,
l'outil étant désormais là.

Mesuré sur une passe : `m4` et `libtool` se sont arrêtés sur

```
bootstrap: error: Prerequisite 'help2man' not found.
```

alors que `help2man` répond dans le chroot — il y a été installé trois heures
APRÈS leur tentative. Le message accuse une absence ; c'est un ordre.

**Relancer la même commande** jusqu'à ce qu'une passe n'apporte plus rien. Les
paquets déjà bâtis sont sautés, le registre étant `stage2.state`.

### Lire les échecs : chercher la cause commune avant les causes propres

Un échec à l'étage 2 en entraîne d'autres, et la liste brute le cache. Sur une
passe de 36 échecs, **28 portaient la même ligne** :

```
/usr/lib/libz.so.1: no version information available
```

Un seul paquet — `zlib` — n'avait pas pu se rebâtir, le chroot gardait donc
celui de l'étage 1, lié aux bibliothèques de l'hôte, et `binutils` puis `gcc`
tombaient derrière. Compter les échecs qui partagent une ligne coûte une
commande et désigne la racine :

```bash
grep -l "<la ligne suspecte>" ~/work/arch-s390x/stage2-log-*.txt | wc -l
```

## 4. Vérifier

```bash
bash scripts/test-chroot.sh        # RESOLVE / ARTEFACT / SONAME / RUN
bash scripts/compare-stages.sh     # un étage en reproduit-il un autre ?
bash scripts/sign-repo.sh          # signer, une fois le dépôt stable
```

### L'étage 3, et ce que « auto-hébergé » veut dire ici

```bash
STAGE_N=3 PKG_GIT_BASE="file://$HOME/work/arch-s390x/recettes-arch-s390x" \
    EL_NOCHECK=1 bash scripts/build-stage2.sh --all
```

Même script, un chiffre de plus : le chroot se peuple depuis **repo2 seul**.
Le premier signe que l'étage 2 a réussi est que ce peuplement ne se replie
PAS sur `CHROOT_PKGS` — les 283 paquets s'installent d'un bloc.

Résultat : 228 sur 229, et les quatre épreuves propres sur repo3.

**La comparaison avec l'étage 2 ne rend pas « identique », et c'est normal.**
267 contenus identiques, 13 différents — mais 110 lignes ajoutées contre 33
retirées. L'étage 3 produit PLUS, parce que son chroot est plus riche :
`gnupg` y gagne `dirmngr_ldap`, `coreutils` son `stdbuf`, `p11-kit` et
`util-linux` leurs complétions. Et les retraits sont le piège du bâtisseur
embarqué : l'étage 2 livrait `build-1.3.0` et `installer-0.7.0`, ses copies
vendues ; l'étage 3 livre `1.4.3` et `1.0.0`, les vraies.

Deux écarts ne sont pas des écarts : `meson` et `setuptools` portent la DATE
de construction dans leur numéro de version.

**Ce qui prouve l'auto-hébergement complet est un étage 4 identique à
l'étage 3**, et la section suivante le donne. L'étage 3 démontre déjà
l'essentiel : la chaîne se régénère sans rien emprunter à l'hôte.

### L'étage 4, et la preuve que la chaîne a convergé

```bash
STAGE_N=4 PKG_GIT_BASE="file://$HOME/work/arch-s390x/recettes-arch-s390x" \
    EL_NOCHECK=1 bash scripts/build-stage2.sh --all
```

Le chroot se peuple depuis **repo3 seul** : 278 paquets d'un bloc, sans
repli sur `CHROOT_PKGS`. Résultat identique à l'étage 3 — 228 sur 229, le
manquant étant `libaio`, dont la source est retirée en amont — et les quatre
épreuves propres sur repo4.

La comparaison avec l'étage 3 donne **279 contenus identiques sur 280, toutes
les versions égales**. Le seul écart est `meson`, dont le numéro de version
de développement porte la date de construction : `d20261020` contre
`d20261021`. Ce n'est pas un défaut d'auto-hébergement, c'est un horodatage.

**La chaîne est donc auto-hébergée** : un étage bâti depuis le précédent
reproduit le précédent.

### Une différence qui OSCILLE se reconnaît à ceci : elle change de camp

L'écart le plus instructif de cette comparaison a d'abord ressemblé à du
bruit. Le `ninja` d'un étage portait 47 fichiers de plus que celui du
suivant : en-têtes `gmock` et `gtest`, bibliothèques, fichiers cmake.

`ninja` déclare `gtest` en `makedepends`. Comme `makepkg` tourne avec
`--nodeps`, rien ne l'installe, et le port ne bâtit pas ce paquet : cmake ne
trouve pas GTest, le télécharge par `FetchContent`, le bâtit, et
`cmake --install` le dépose dans le paquet avec le reste.

Le piège est dans la suite. Un `ninja` ainsi contaminé, installé dans le
chroot de l'étage suivant, y fournit `/usr/lib/cmake/GTest/GTestConfig.cmake`.
Cmake le trouve alors, ne vendorise rien, et l'étage produit un `ninja`
propre — qui prive l'étage d'après de GTest, qui contamine à nouveau. **Deux
étages consécutifs ne peuvent jamais être identiques tant que la sortie d'un
paquet dépend de ce qui se trouve dans le chroot.** Comparer un étage de plus
ne résout rien : l'écart change de camp, il ne disparaît pas.

Les deux journaux de construction le disent en une ligne chacun, et c'est là
qu'il faut regarder avant de conclure au bruit :

```
-- Could NOT find GTest (missing: GTEST_LIBRARY ...)     puis _deps/googletest-build
-- Found GTest: /usr/lib/cmake/GTest/GTestConfig.cmake (found version "1.16.0")
```

Le correctif est dans `patches/pkgbuild/ninja.sh` : il retire googletest de
`$pkgdir` en fin de `package()`. L'épreuve qui le valide n'est pas que le
paquet soit propre, mais qu'il le soit **dans le chroot où cmake vendorise
quand même** — sinon on mesure l'absence de la cause, pas l'effet du
correctif.

Un retrait laisse des répertoires vides, et un répertoire vide est lui-même
une différence entre deux étages : la première version du correctif a laissé
`usr/lib/pkgconfig/` derrière elle, et la comparaison l'a vu.

### Ne pas prendre la liste des horodatages pour acquise

Entre l'étage 2 et l'étage 3, `meson` ET `setuptools` différaient par leur
date. Entre l'étage 3 et l'étage 4, `setuptools` est identique et seul
`meson` diffère. Un paquet qui porte une date dans sa version ne diffère que
si les deux étages tombent de part et d'autre de minuit. « C'est juste la
date » est une conclusion à tirer du diff, jamais une hypothèse à poser
avant de le lire.

### Ce que l'étage 2 donne quand il est fini

```
== 1. RESOLVE ==   ok    resolver satisfied
== 2. ARTEFACT ==  ok    no multiarch, no lib64, no dist-packages, no usr/local
== 3. SONAME ==    ok    every requested soname has a provider
== 4. RUN ==       ok    bash, libc, ls, tar, find, sed, pacman
== Verdict ==      the repository resolves, is clean, and runs.
```

**C'est le seul verdict qui compte**, et la section suivante dit à quoi il
s'oppose. 228 paquets sur 229 : seul `libaio` manque, sa source ayant été
retirée par son amont.

**Deux pièges se sont révélés à ce moment précis**, et ni le registre ni les
journaux ne les voyaient :

- **Une dépendance impossible.** Trois paquets bâtis avant que `zlib` ne soit
  réparé portaient `libz.so=libz.so-64`, que makepkg avait déduite d'une
  bibliothèque sans version de soname. Corrects pour le registre, faux dans le
  dépôt. Seule l'épreuve RESOLVE le dit.
- **Un chemin absolu au lieu d'un soname.** Cinq paquets inscrivaient
  `NEEDED [/usr/lib/libz.so]`, ce qu'un éditeur de liens ne fait que si la
  bibliothèque n'a pas de champ SONAME — et le zlib de l'étage 1 n'en a pas.
  Seule l'épreuve SONAME le dit.

Dans les deux cas le remède est le même : **rebâtir en nommant le paquet**,
ce qui prime désormais sur le registre. Un paquet bâti avant la réparation
d'une bibliothèque qu'il utilise est à refaire, et rien ne le signale tout
seul.

### Ce que `test-chroot.sh` donne sur un dépôt d'étage 1 SEUL

Il ne rend pas un verdict propre, et ce n'est pas un défaut : il mesure un
dépôt que l'étage 2 n'a pas encore refait. Sans ce relevé de référence, un
lecteur ne peut pas distinguer une régression de l'état normal.

- **RUN passe, et c'est le résultat qui compte.** Les dix paquets d'un rootfs
  minimal s'installent, le chroot démarre, et `bash`, la libc, `ls`, `tar`,
  `find` et `sed` répondent. L'étage 1 produit donc un système s390x qui
  s'exécute. Seul `pacman` n'y démarre pas, sur `libgpgme.so.11` — un soname
  de l'hôte, donc de la même famille que ci-dessous.
- **SONAME** signale deux groupes. Douze sonames à la version de l'HÔTE dont
  le dépôt livre une autre version : artefact de construction, l'étage 1
  compilant hors du chroot. Cinq sans aucun fournisseur — `libfido2`,
  `libselinux`, `libtcl8.6`, `libtk8.6`, `libpython3.13` — captés sur
  l'hôte. Le cas de tcl en montre la mécanique : le portage livre tcl 9,
  donc `libtcl9.0.so`, et le module `_tkinter` de python s'est lié au
  `libtcl8.6` de l'hôte, tk n'étant pas empaqueté du tout. Dans le chroot
  ces bibliothèques n'existent pas : le module se liera autrement ou ne se
  bâtira pas, ce qui change le contenu du paquet d'un étage à l'autre.
  C'est `compare-stages.sh` qui le dira.
- **ARTEFACT** signale les paquets Python, qui portent des chemins
  `dist-packages`. L'étage 1 compile avec l'interpréteur de l'hôte ; c'est la
  disposition Debian, et l'étage 2 la refait en disposition Arch.
- **RESOLVE** échoue sur les paquets que l'étage 1 ne sait pas bâtir.

**La règle** : à l'étage 1, ces quatre sections échouent ainsi. Après
l'étage 2, la MÊME commande doit être propre. C'est la comparaison qui prouve
quelque chose, pas le relevé isolé.

### Un registre d'étage survit à la machine qui l'a écrit

`stageN.state` et `repoN` se restaurent avec le reste d'une sauvegarde, et
rien ne dit de quelle exécution ils viennent. Un nom qui s'y trouve est sauté,
donc jamais rebâti — et la comparaison porte alors sur un artefact d'une
autre machine sans que rien ne le signale.

Vu sur un étage 3 : cinq paquets dataient de trois jours plus tôt, d'une
tentative sur la machine précédente. Les dates le disent en une commande :

```bash
ls -l --time-style=+%m-%d_%H:%M ~/work/arch-s390x/repo3/s390x/*.pkg.tar.zst
```

Un étage qu'on veut PROUVER se recommence à neuf : déplacer `repoN` et
`stageN.state` ailleurs — les déplacer, pas les effacer — et relancer.

### D'ABORD : le dépôt comparé est-il bien celui de cette exécution ?

`repo2/s390x` peut mélanger deux choses — les paquets que l'exécution en cours
a bâtis, et ceux qu'une exécution antérieure y a laissés ou qu'une restauration
y a remis. Comparer les deux sans le savoir, c'est mesurer un étage 2 qui
n'existe pas.

Le registre tranche : un paquet compte pour cette exécution si son `pkgbase`
est dans `stage2.state`.

```bash
W=~/work/arch-s390x; tot=0; frais=0
for f in $W/repo2/s390x/*.pkg.tar.zst; do
    case "$f" in *.sig) continue;; esac
    tot=$((tot + 1))
    pb=$(bsdtar -xOf "$f" .PKGINFO | sed -n 's/^pkgbase = //p')
    pn=$(bsdtar -xOf "$f" .PKGINFO | sed -n 's/^pkgname = //p')
    grep -qxF "${pb:-$pn}" $W/stage2.state && frais=$((frais + 1))
done
echo "$frais de $tot bâtis par cette exécution"
```

Tant que les deux nombres diffèrent, l'étage 2 n'est pas fini : relancer.
Un verdict rendu sur un dépôt mélangé ne dit rien.

### Lire `compare-stages.sh` : ce que l'étage 2 répare, chiffré

La comparaison ne rend pas un verdict binaire utile tant que l'étage 2 n'a pas
tourné sur le même étage 1. Elle montre en revanche, en clair, CE QUE l'étage 2
apporte — et trois mécanismes expliquent la quasi-totalité des écarts :

- **La disposition Python.** Des centaines de chemins sous
  `usr/lib/python3/` (dist-packages) n'existent que du côté étage 1. L'étage 2
  les range sous `usr/lib/python3.<x>/site-packages`.
- **La version d'interpréteur captée.** Des chemins sous
  `usr/lib/python3.<version de l'hôte>` n'apparaissent que du côté étage 1,
  alors que les DEUX dépôts livrent le même python. Ce n'est donc pas une
  dérive d'amont : c'est l'interpréteur de l'hôte qui s'est invité.
- **Le répertoire multiarch.** Des chemins sous
  `usr/lib/<triplet>-linux-gnu`, la disposition Debian, du seul côté étage 1.

Côté déclarations, l'écart dominant est que l'étage 1 annonce un soname NU
— `provides = libacl.so` — là où l'étage 2 l'annonce VERSIONNÉ —
`libacl.so=1-64`. Systématique, et sans rapport avec un paquet en
particulier.

**Un paquet d'étage 1 n'est pas le jumeau du sien à l'étage 2**, et cela se
mesure. La bibliothèque zlib bâtie sur l'hôte n'expose AUCUN symbole
versionné ; celle que l'étage 2 produit en expose 58 :

```bash
readelf -V /usr/lib/libz.so.1 | grep -c ZLIB_
```

Ce qui s'y lie l'ignore silencieusement jusqu'à ce qu'un outil s'en plaigne —
« no version information available » — et un chroot qui garde la première
version arrête la chaîne de compilation entière.

**Ce qui mérite un regard** est le reste : un soname qu'un seul étage
fournit, une dépendance qu'un seul déclare. Les trier revient à retirer les
groupes où les deux côtés portent les mêmes noms à la version près :

```bash
grep -E "^[<>] (provides|depend) = " ~/work/arch-s390x/compare-stages.txt
```

### L'épreuve RESOLVE voit ce que le registre ne voit pas

Comparer `stage1.state` à `STAGE1_PACKAGES` dit ce qui n'a pas BÂTI. Cela ne
dit rien d'un paquet qui a bâti, est entré au dépôt, et que personne ne peut
installer parce qu'une de ses dépendances n'a jamais été listée — le nom
manquant n'étant pas dans la liste, aucune comparaison à la liste ne le
trouve. Il faut demander à pacman de résoudre le dépôt ENTIER :

```bash
cat > /tmp/r.conf <<'CONF'
[options]
Architecture = s390x
SigLevel = Never
[core]
Server = file:///home/<compte>/work/arch-s390x/repo/s390x
CONF
sudo pacman --config /tmp/r.conf --dbpath /tmp/r.db -Sy
mapfile -t ALL < <(sudo pacman --config /tmp/r.conf --dbpath /tmp/r.db -Sl core | awk '{print $2}')
sudo pacman --config /tmp/r.conf --dbpath /tmp/r.db -Sp "${ALL[@]}" 2>&1 \
  | grep -oE "dependency '[^']+'" | sort -u
```

Chaque nom sorti est soit un paquet que l'étage 1 ne peut pas bâtir, soit un
trou dans la liste. C'est ainsi que `python-tomlkit` a été trouvé : dépendance
d'exécution de hatchling, jamais listée, donc jamais signalée.

## 1 bis. Le miroir des recettes

Les 229 recettes viennent d'un seul hôte. Quand il tombe, tout paquet dont
la recette n'est pas déjà clonée s'arrête — mesuré : aucune réponse ICMP,
443 fermé, pendant des heures, quand GitHub et GNU répondaient en 200 ms.

Le miroir s'en affranchit. Depuis une machine qui atteint l'amont :

```bash
# un clone NU par recette : historique complet, pas la tête du jour
git clone --mirror https://gitlab.archlinux.org/archlinux/packaging/packages/<nom>.git \
    recettes-arch-s390x/<nom>.git
```

**Ce qui fait la différence entre un miroir utile et une copie inutile** :
chaque commit nommé par `upstream.lock` doit s'y trouver. Un `--depth 1`
donne les recettes d'aujourd'hui, pas celles contre lesquelles les crochets
sont écrits. Le contrôle, dépôt par dépôt :

```bash
git --git-dir recettes-arch-s390x/<nom>.git cat-file -e <commit-du-verrou>^{commit}
```

Puis on branche le portage dessus, aux deux étages :

```bash
PKG_GIT_BASE="file://$HOME/work/arch-s390x/recettes-arch-s390x" \
    bash scripts/build-stage1.sh
```

**Vérifié** : 229 dépôts nus, 55 Mo, et les 186 commits épinglés tous
présents. Clone, `--depth 1` et résolution du commit fonctionnent en local.

**Le miroir suit la liste, et ne la devance pas.** Il est fabriqué à partir
des noms de `STAGE1_PACKAGES` : ajouter un paquet à la liste veut dire cloner
sa recette en plus, sinon il échouera comme si l'amont était tombé.

**L'amont compte les requêtes.** Six clones en parallèle font répondre
`HTTP 429 Too Many Requests` à partir du deux-centième dépôt environ, et des
réessais rapides aggravent ce qu'ils tentent de réparer. Deux en parallèle,
et une attente qui se compte en minutes sur un 429.

### Les recettes ne suffisent pas : miroiter aussi les SOURCES du même hôte

Un miroir de recettes laisse passer ce dont une recette a besoin pour se
bâtir. Deux dépôts du même hôte ne sont pas des recettes et manquent donc au
miroir :

```bash
git clone --mirror https://gitlab.archlinux.org/archlinux/python-bootstrap.git
git clone --mirror https://gitlab.archlinux.org/pacman/pacman.git
```

**Le premier arrête tout.** `python-bootstrap` est le bâtisseur embarqué par
lequel Arch brise le cycle de l'empaquetage Python, et `python-setuptools`
n'a pas d'autre chemin : son arbre source masque le setuptools installé, donc
il ne peut pas se servir de backend à lui-même. Sans lui :

- l'étage 1 perd `python-setuptools`, et `python-lark-parser` derrière lui,
  qui exige une version que la distribution ne livre pas ;
- l'étage 2 **ne démarre pas du tout** : `python-setuptools` est nommé dans
  `CHROOT_PKGS`, et le chroot se peuple depuis repo1.

Il n'existe nulle part ailleurs — pas de miroir GitHub, vérifié : 404. Un
miroir des recettes sans ces deux dépôts laisse le portage à la merci de
l'hôte qu'il croyait avoir quitté.

## 4 bis. Un échec sur deux n'est pas un bogue

### Sept échecs sont normaux, et la liste les nomme

Une passe d'étage 1 n'est JAMAIS propre. Huit paquets ne peuvent pas se bâtir
hors du chroot : il leur faut le llvm, le libxml2 ou le rust que le portage
produit lui-même, ou bien l'amont a retiré leur source. Ce n'est pas un défaut à
corriger, c'est un trou de fermeture que l'étage 2 comble.

Ils sont nommés dans `STAGE1_EXPECTED_FAILURES`, à la fin de
`scripts/packages.sh`, et la raison de chacun est écrite à côté du paquet dans
la liste principale. Le résumé de fin de passe les sépare tout seul :

```
== stage 1: 220 built, 8 failed ==
  expected (see STAGE1_EXPECTED_FAILURES): clang lld rust libxslt libaio postgresql maturin python-rpds-py
  no unexpected failure
```

**C'est la ligne `UNEXPECTED` qui compte.** Tant qu'elle n'apparaît pas, la
passe s'est bien passée, quel que soit le nombre d'échecs. Et si un paquet
attendu se met à bâtir, le résumé le dit aussi — la liste est alors à alléger,
ce qui veut dire que l'étage 1 va plus loin qu'avant.

### Le reste

Relancer d'abord, diagnostiquer ensuite. Sur une passe observée, la moitié
des échecs venaient du réseau et se sont effacés d'eux-mêmes à la relance :
un `curl` qui ne connecte pas en 114 ms, un miroir qui rend un 5xx, un clone
interrompu. Le journal dit `FAIL <paquet>` du même ton que pour un vrai
défaut, et rien ne distingue les deux à l'œil.

Les séparer coûte une commande :

```bash
grep -qE "unable to access|Failed to connect|returned error: 5|Could not resolve" \
    ~/work/arch-s390x/log-<paquet>.txt && echo RESEAU || echo structurel
```

**LES RECETTES VIENNENT TOUTES D'UN SEUL HÔTE.** Les 235 recettes sont
clonées depuis le GitLab d'Arch. Quand il tombe — mesuré : ICMP sans réponse,
HTTP qui expire à 15 s, pendant que GitHub et GNU répondent en 200 ms —
chaque paquet dont la recette n'est pas déjà clonée échoue, et une passe
entière n'apprend rien. Une recette déjà clonée dans `~/work/arch-s390x/pkg/`
continue de bâtir : ce répertoire est, de fait, le miroir des recettes.

Ne pas relancer en boucle pendant une panne d'amont : attendre qu'il réponde.

## 5. Déployer une VM, et y installer ERPLibre

Les étages 1 à 4 produisent un dépôt de paquets. Cette section en fait une
image de machine virtuelle amorçable, la publie, et la rend choisissable
depuis `TODO › Execute › Deploy › QEMU/KVM` d'ERPLibre.

**Ce que l'image contient, et ce qu'elle ne contient pas** : un Arch s390x qui
amorce, cloud-init, un pacman qui pointe sur le dépôt du portage — et rien
d'autre. **ERPLibre n'y est pas.** Il s'installe après l'amorçage, par son
propre installateur, comme sur n'importe quelle autre distribution. C'est la
condition pour que le déploiement ÉPROUVE l'installateur ; une image où
ERPLibre serait déjà posé à la main ne prouverait que le talent de celui qui
l'a posée. Deux scripts de provisionnement ont existé ici et ont été
supprimés pour cette raison.

### 5.1 Bâtir l'image

`build-image.sh` partitionne un fichier, monte la partition en boucle, y
installe les paquets depuis le dépôt local, écrit le secteur d'amorçage avec
`zipl`, et démonte. Tout passe
par un `chroot` et non par `pacman --root` : `--root` n'exécute PAS les
scriptlets d'installation, et une image bâtie ainsi part avec un magasin de
certificats vide — chaque client TLS échoue alors sur `error adding trust
anchors`, très loin de la cause.

```bash
W=$HOME/work/arch-s390x
cd ~/git/archlinux-s390x
REPO2=$W/repo4/s390x \
IMG=$W/arch-s390x-cloud.img \
SIZE=8G \
EL_CLOUD_INIT=1 \
EL_REPO_SERVER=192.168.123.1:8081 \
EL_SSH_PUBKEY=$HOME/.ssh/id_ed25519.pub \
bash scripts/build-image.sh
```

`REPO2` désigne le dépôt source malgré son nom : il vaut pour n'importe quel
étage, et c'est le dernier qu'on veut ici. `EL_REPO_SERVER` prend un
`hôte:port`, pas une URL, et écrit la configuration pacman de l'INVITÉ.
`SIZE=8G` au lieu des 24 Go par défaut : l'image publiée doit se télécharger,
et le déploiement l'agrandit de toute façon (§ 5.4). Deux variables
supplémentaires existent et ne sont pas utilisées ici : `EL_EXTRA_CA`, qui
ancre une autorité de certification interne pour un réseau derrière un proxy
qui réécrit TLS, et `EL_ROOT_PASSWORD`. Sans clé NI mot de passe, la console
série demande une authentification que rien ne peut fournir — le script le
dit, il ne l'invente pas.

**Pourquoi une table de partitions sur une image qui n'en avait pas.** Le
noyau reçoit son périphérique racine sur la ligne de commande, avant que le
moindre espace utilisateur existe pour résoudre un nom. Des formes qu'il sait
résoudre seul, seules `PARTUUID=` et `PARTLABEL=` désignent un système de
fichiers plutôt qu'un rang d'énumération, et les deux exigent une table.
`root=/dev/vda` désigne, lui, le premier périphérique virtio-blk dont le
sondage ABOUTIT — et le sondage est asynchrone. Un invité portant une seed
cloud-init en second virtio-blk peut démarrer avec la seed en `/dev/vda` et
paniquer sur `No working init found`, un iso9660 monté en racine. Plus il a
de processeurs, plus le petit périphérique gagne. L'image porte donc un MBR,
une partition, et `root=PARTUUID=5390a7c4-01` ; `DISK_ID` permet d'en changer.

Vérifié : **194 paquets**, 8 Gio apparents pour **1,8 Gio sur le disque**
(l'image est creuse). Recomptable sans monter quoi que ce soit — en donnant à
`debugfs` le début de la partition, puisque le système de fichiers ne
commence plus à l'octet 0 :

```bash
debugfs -R "ls -p /var/lib/pacman/local" "$W/arch-s390x-cloud.img?offset=1048576" \
  2>/dev/null \
  | awk -F/ 'NF>5 && $3 ~ /^04/ {print $6}' | grep -vE '^\.\.?$' | wc -l
```

Et que l'amorçage tient, lui, se vérifie sur l'image elle-même :

```bash
sfdisk -l $W/arch-s390x-cloud.img | tail -2   # une partition, secteur 2048
head -c 4 $W/arch-s390x-cloud.img             # zIPL : le record survit au MBR
head -c 512 $W/arch-s390x-cloud.img | tail -c 2 | xxd -p   # 55aa
```

### 5.2 Publier l'image

Le format brut sert à la construction, pas au transport : converti en qcow2
compressé, le même contenu passe de 1,8 Gio à 665 Mio. Le nom de fichier et
celui de la somme ne sont pas libres — ERPLibre cherche `{image}.SHA256` pour
la distribution `arch`, et l'image sous le nom exact ci-dessous.

```bash
qemu-img convert -c -O qcow2 \
    $W/arch-s390x-cloud.img \
    $W/repo4/images/Arch-Linux-s390x-cloudimg.qcow2
cd $W/repo4/images
sha256sum Arch-Linux-s390x-cloudimg.qcow2 > Arch-Linux-s390x-cloudimg.qcow2.SHA256
sha256sum -c Arch-Linux-s390x-cloudimg.qcow2.SHA256
```

**La somme se republie avec l'image, toujours.** C'est elle, et non le nom
du fichier, qui périme la copie en cache des hôtes qui ont déjà déployé : le
déploiement relit le `.SHA256` même quand il saute le téléchargement, et
reprend l'image dès que les deux divergent. Une image remplacée sans sa somme
arrête le déploiement suivant ; une image publiée sans somme du tout ne se
rafraîchit jamais.

Rien d'autre à lancer : le serveur du § 1 bis sert déjà `repo4` à la racine,
donc `repo4/images/` répond en `/images/` sur le même port que le dépôt
pacman. Vérifié : `HTTP/1.0 200 OK` sur
`http://192.168.123.1:8081/images/Arch-Linux-s390x-cloudimg.qcow2`, et
`sha256sum -c` qui répond `OK`.

### 5.3 Ce qu'il a fallu changer côté ERPLibre

Trois endroits, parce qu'Arch ne publie aucune image s390x en amont et que le
code supposait que toute image vient de son éditeur :

- `script/qemu/deploy_qemu.py` — `"arch"` ajouté à `S390X_DISTROS`, et
  `image_candidates()` rend l'URL locale quand l'architecture est s390x.
- la base de cette URL est `EL_ARCH_S390X_BASE`, dont le défaut est l'hôte du
  pont libvirt. Servir depuis ailleurs ne demande donc aucune modification du
  code, seulement la variable d'environnement.
- `script/todo/qemu_menu.py` — `"arch"` ajouté à `_QEMU_S390X_DISTROS`. Ce
  n'est pas un oubli de conception mais une copie de repli : le menu doit
  s'afficher même quand `deploy_qemu.py` n'est pas importable. Une liste
  modifiée d'un seul côté donne un menu qui propose un choix que le
  déploiement refuse, ou l'inverse.

### 5.4 Déployer, puis installer

Depuis `TODO › Execute › Deploy › QEMU/KVM`, choisir l'architecture `s390x`
puis la distribution `arch`. Le déploiement télécharge l'image, vérifie sa
somme, l'agrandit (`qemu-img resize`, 25 Gio par défaut — au premier amorçage
cloud-init étend la partition avec `growpart`, puis le système de fichiers
qu'elle porte ; sans `growpart` il n'étendrait ni l'une ni l'autre et ne le
dirait nulle part), crée la VM, puis lance
l'installation d'ERPLibre dans l'invité.

Le journal est écrit sur l'hôte, sous
`~/.erplibre/qemu-install/<horodatage>/erplibre-arch.log`, et se termine par
`__ERPLIBRE_EXIT__ <code>`. Vérifié de bout en bout : `__ERPLIBRE_EXIT__ 0`,
Odoo 18.0, 131 chemins d'addons, `erplibre.service` actif.

`/web/login` rend alors **303 et non 200** : aucune base de données n'existe,
et Odoo redirige vers le sélecteur. C'est le comportement attendu — le
déploiement installe, il ne crée pas de base. L'écran `a` du suivi
d'installation offre `./script/database/db_restore.py` pour en créer une.

### 5.5 Les pièges, et ce que chacun donne à l'écran

| À l'écran | La cause réelle |
|---|---|
| `Image déjà présente, téléchargement ignoré`, puis `Somme sha256 NON conforme : image reprise une fois.` | ce n'est pas une panne, c'est le rattrapage normal après une republication. Le nom de cache `/var/lib/libvirt/images/arch-linux-s390x-cloudimg.qcow2` ne porte pas de version : ce qui périme une image gardée, c'est la SOMME, relue à chaque déploiement. Le déploiement la reprend seul |
| `Somme sha256 NON conforme !`, et le déploiement s'arrête | l'image a été republiée sans régénérer son `.SHA256`. Un second écart porte sur des octets fraîchement téléchargés : il arrête tout, et supprime l'image |
| l'image sort avec des paquets d'un autre étage | `pacman-image.conf` traînait d'une construction précédente. `build-image.sh` le réécrit désormais quand il désigne un autre dépôt, et le dit |
| `invalid or corrupted package`, sans nommer lequel | le cache de paquets pacman porte une version périmée. Le vider |
| `Kernel panic - not syncing: No working init found.` | l'image est antérieure à la table de partitions et son secteur d'amorçage dit `root=/dev/vda`. La seed cloud-init lui a pris la lettre. Reconstruire ; à défaut, déployer avec moins de vCPU fait gagner la course sans la supprimer |
| `⚠ sommes injoignables, image NON vérifiée : HTTP Error 404` | le fichier `.SHA256` n'a pas été publié à côté de l'image. Le déploiement CONTINUE sans vérifier — et c'est LÀ que le cache gèle : sans somme à comparer, une image republiée n'est plus jamais retéléchargée. Même effet avec `--no-verify` |
| le serveur sert encore l'ancienne racine | `systemctl enable --now` NE REDÉMARRE PAS une unité déjà active. `systemctl restart` après toute modification de l'unité |
| l'installation s'arrête sur une extension Python qui ne compile pas | `install_arch_linux.sh` était la seule distribution sans fragment `script/install/S390x/` : presque aucune roue n'existe pour cette architecture, donc chaque extension se compile et réclame sa bibliothèque système |

## 6. Ce qui échoue, et ce que le message veut dire

| À l'écran | La cause réelle |
|---|---|
| `asm/sigcontext.h: No such file` | les ponts multiarch manquent — relancer `bootstrap-pacman.sh` |
| `sdt-config.h: No such file` | idem, le pont `sys/` n'a pas été posé |
| `libalpm.so.16: cannot open shared object file` | `ldconfig` n'a pas tourné après l'installation de pacman |
| `cd: /build/<nom>: No such file` | `$WORK/pkg` absent côté hôte, le montage bind a échoué |
| `makepkg: command not found` | `bootstrap-pacman.sh` n'a pas été lancé |
| `could not read Username for gitlab` | le paquet demandé n'existe pas chez Arch sous ce nom |

Chacune de ces lignes désigne autre chose que sa cause. C'est la signature de
ce portage : l'échec se manifeste loin de son origine.
