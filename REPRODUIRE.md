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

## 2. Étage 1 — 92 paquets

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
sont sautés. Pour en forcer un, retirer son nom du registre d'état.

**Vérifié jusqu'à gcc inclus** au moment d'écrire ; la suite ne l'est pas.

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

## 4 bis. Un échec sur deux n'est pas un bogue

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
