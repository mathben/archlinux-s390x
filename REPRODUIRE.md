# Refaire les étages 1 et 2, à la main

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

**Non vérifié dans cette passe.** L'étage 2 a tourné par le passé sur l'autre
hôte ; il n'a pas été rejoué depuis la reconstruction.

## 4. Vérifier

```bash
bash scripts/test-chroot.sh        # RESOLVE / ARTEFACT / SONAME / RUN
bash scripts/compare-stages.sh     # un étage en reproduit-il un autre ?
bash scripts/sign-repo.sh          # signer, une fois le dépôt stable
```

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
  `libselinux`, `libtcl8.6`, `libtk8.6`, `libpython3.13` — que des paquets
  ont captés sur l'hôte et que le portage n'empaquette pas.
- **ARTEFACT** signale les paquets Python, qui portent des chemins
  `dist-packages`. L'étage 1 compile avec l'interpréteur de l'hôte ; c'est la
  disposition Debian, et l'étage 2 la refait en disposition Arch.
- **RESOLVE** échoue sur les paquets que l'étage 1 ne sait pas bâtir.

**La règle** : à l'étage 1, ces quatre sections échouent ainsi. Après
l'étage 2, la MÊME commande doit être propre. C'est la comparaison qui prouve
quelque chose, pas le relevé isolé.

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

## 5. Ce qui échoue, et ce que le message veut dire

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
