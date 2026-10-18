# Arch Linux sur s390x — état du portage

Objectif : **ERPLibre tourne sur Arch Linux s390x.** Terminé quand ERPLibre
fonctionne, pas quand les paquets compilent.

## Où est quoi

| | |
|---|---|
| Machine | la VM de developpement s390x, Ubuntu, joignable par un rebond ssh |
| Dépôt du portage | `~/git/archlinux-s390x` — trois distants : deux GitHub, une forge |
| Espace de travail | `~/work/arch-s390x` |
| Dépôt étage 1 | `~/work/arch-s390x/repo/s390x` |
| Dépôt étage 2 | `~/work/arch-s390x/repo2/s390x` |
| Chroot étage 2 | `~/work/arch-s390x/rootfs-stage2` |
| Image de déploiement | `~/work/arch-s390x/arch-s390x.img` — 24 Go, ext4, `LABEL=ARCH_S390X` |
| Domaine libvirt | `arch-s390x`, réseau NAT `default`, autostart |
| Dépôt servi aux invités | `arch-s390x-repo.service`, l'étage 2 en HTTP sur le pont NAT |
| Console de la VM | `~/work/arch-s390x/vm-console.txt` |
| Registres | `stage1.state`, `stage2.state` |

**Ne pas toucher** : `/var/lib/libvirt` (VM d'autres travaux). Le `/tmp` de
cette machine est partagé **et** en tmpfs — utiliser un sous-répertoire à soi.

## Ce que l'hôte doit porter

Le portage bâtit ses paquets dans un chroot peuplé depuis `repo2`, mais
l'amorçage de ce chroot, la signature et l'amorçage des VM se font avec des
outils de l'HÔTE. Un hôte neuf n'en a aucun, et rien ne le dit avant que
`build-stage2.sh` échoue sur `makepkg: command not found`.

```bash
sudo apt install pacman-package-manager libarchive-tools fakeroot \
     build-essential arch-install-scripts s390-tools \
     qemu-system-s390x qemu-utils libvirt-clients libvirt-daemon-system virtinst
```

`pacman-package-manager` porte `pacman`, `makepkg`, `repo-add` et
`pacman-key` ; le paquet nommé `pacman` est un jeu de labyrinthe. `bsdtar`
vient de `libarchive-tools`, `zipl` de `s390-tools`.

**Cette liste sert à REPRENDRE, pas à bâtir.** Elle suffit pour servir et
signer un dépôt restauré, ou construire une image. Une passe de construction
veut davantage : `bootstrap-pacman.sh` installe sa propre liste de paquets
`-dev`, bâtit pacman depuis les sources dans `/usr/local/bin` — plus récent
que celui d'Ubuntu — et pose `CHOST`, `MAKEFLAGS` et `SRCDEST` dans
`/etc/makepkg.conf`. Le lancer avant l'étage 1, une fois par hôte.

**L'hôte n'a pas à être la même version d'Ubuntu qu'avant.** L'étage 1 avait
été bâti contre les bibliothèques de l'hôte, mais il n'est plus nécessaire :
`repo2` le remplace et un chroot se peuple depuis lui seul. Ce que la dérive
de l'hôte peut encore toucher — version de `pacman`, de `makepkg` — n'a pas
été mesuré sur deux versions différentes.

## Le chemin complet

De rien à une VM qui sert ERPLibre, dans l ordre. Chaque étape suppose la
précédente ; les sections qui suivent détaillent chacune.

```bash
# 1. La distribution
EL_NOCHECK=1 bash scripts/build-stage2.sh --all   # depuis l étage 1
bash scripts/sign-repo.sh                         # 277 signatures + la base
bash scripts/serve-repo.sh install                # la servir aux invités

# 2. Une image
EL_REPO_SERVER=<hôte:port> EL_VERIFY_REPO=1 \
  EL_SSH_PUBKEY=~/.ssh/<clé>.pub bash scripts/build-image.sh

# 3. ERPLibre dedans, et l image distribuable qui en sort
bash scripts/build-erplibre-image.sh

# 4. La faire tourner
bash scripts/install-libvirt-domain.sh && virsh --connect qemu:///system start arch-s390x
```

Le déploiement depuis ERPLibre prend le relais à l étape 4 :
`EL_LOCAL_IMAGE=<image> python3 script/qemu/deploy_qemu.py --distro arch
--arch s390x --name <nom> --ssh-key <clé.pub>`.

## Construire la distribution

```bash
cd ~/git/archlinux-s390x
bash scripts/build-stage1.sh                 # toute la liste
bash scripts/build-stage1.sh gperf rsync     # à la demande, écrase le registre
EL_NOCHECK=1 bash scripts/build-stage2.sh --all
bash scripts/build-stage2.sh libxml2         # un paquet
STAGE_N=3 bash scripts/build-stage2.sh --all # l étage 3, même mécanique
bash scripts/compare-stages.sh               # l étage 3 reproduit-il le 2 ?
bash scripts/test-chroot.sh                  # RESOLVE / ARTEFACT / SONAME / RUN
```

Chaque passe se termine par un RESOLVE : pacman dit si tout le dépôt
s installe ensemble. C est ce qui manquait, et six trous y avaient vécu.

Toujours en arrière-plan, la sortie dans un fichier :

```bash
setsid nohup bash scripts/build-stage2.sh --all > ~/work/arch-s390x/out.txt 2>&1 < /dev/null &
```

`EL_STALL_MIN` (défaut 45) tue une construction muette ; `EL_NOCHECK=1` saute
les suites de tests, à réserver à la première passe.

Un paquet que `stage2.state` nomme déjà est sauté : **retirer son nom du
registre est la façon de demander sa reconstruction**, y compris après une
retouche de son crochet.

## Déployer

La VM est un domaine libvirt, défini une fois pour toutes :

```bash
bash scripts/install-libvirt-domain.sh   # définit, pose le crochet, autostart
# --connect qemu:///system, comme le script. Sans lui, virsh choisit son URI
# par défaut selon l appartenance de l utilisateur au groupe libvirt et selon
# que libvirtd tourne : il peut répondre une liste VIDE, sans erreur, pour un
# domaine qui existe. Être explicite retire cette variable du problème.
virsh --connect qemu:///system start arch-s390x
virsh --connect qemu:///system console arch-s390x      # Ctrl-] pour se détacher
virsh --connect qemu:///system domifaddr arch-s390x    # l adresse donnée par DHCP
```

`scripts/run-vm.sh detach` amorce la même image hors libvirt, pour essayer une
variante sans toucher au domaine. Il REFUSE de démarrer tant que le domaine
tourne, et le crochet refuse l inverse : deux écrivains sur une image ext4 la
détruisent, et libvirt ne sait rien d un qemu qu il n a pas lancé.

L invité a son propre dépôt pacman, servi par l hôte : aucun miroir Arch ne
publie s390x, donc sans lui `pacman` ne peut rien installer. Il ne sert QUE
l étage 2 — livrer un paquet d étage 1 à une cible y remettrait la
contamination que tout l amorçage a servi à retirer.

```bash
bash scripts/sign-repo.sh                                  # signer, une fois
bash scripts/serve-repo.sh install                         # servir, une fois
# DANS l invité -- et l image ne porte pas ce script. build-image.sh ne l y
# copie que si EL_REPO_SERVER est posé, l exécute, puis l efface. Sur une
# image bâtie sans cette variable, il faut l y porter :
#   scp scripts/setup-guest-pacman.sh root@<invité>:/tmp/
#   ssh root@<invité> bash /tmp/setup-guest-pacman.sh <hôte:port> --verify
bash /tmp/setup-guest-pacman.sh <hôte:port> --verify
```

`--verify` prend la clé du portage dans le trousseau de pacman, la signe
localement — pacman se fie à une clé signée, pas à une clé présente — et passe
`SigLevel` à `Required DatabaseRequired`. Sans lui, l invité lit le dépôt sans
rien vérifier.

Une image neuve se construit d un bout à l autre, et `EL_REPO_SERVER` lui pose
son dépôt au passage :

```bash
IMG=~/work/arch-s390x/neuve.img EL_REPO_SERVER=<hôte:port> \
  EL_SSH_PUBKEY=~/.ssh/vm_s390x.pub bash scripts/build-image.sh
```

Le script REFUSE d écraser une image existante. Il lance dans un chroot les
scriptlets que `pacman --root` saute — l hôte est s390x, donc les binaires de
l invité y tournent — sans quoi l image part sans paquet CA, sans clés d hôte
ssh et sans les comptes système dont pacman et initdb ont besoin.

L invité AMORCE SEUL : `build-image.sh` fait écrire à zipl l enregistrement
d amorçage, le domaine n a plus de `<kernel>`, et le noyau qui tourne est celui
que l image porte. `run-vm.sh` garde le mode ancien pour une image que zipl n a
jamais touchée — `KERNEL=` vide demande l IPL, une valeur demande le `-kernel`.
Monter l image exige que la VM soit éteinte.

`build-erplibre-image.sh` va plus loin : il amorce cette image, y installe
ERPLibre par ssh, l éteint proprement, puis RETIRE l identité machine — clés
d hôte ssh, machine-id, journaux, clé de construction. Ce qui reste est le
produit ; ce qui part est ce qui ferait de chaque copie le clone d une
machine existante.

## Où on en est

- **Étage 1 : 193 paquets**, `RESOLVE ok`, `ARTEFACT ok`, `RUN ok`.
- **Étage 2 : 184 paquets**, dont gcc 16.2.1, glibc 2.44, rust, llvm et clang,
  postgresql 18.6, python 3.14, systemd 261, openssh — et le noyau. Test de
  fumée du chroot : **11 ok, 0 échec, 0 dérive connue**.
- **Une VM qui amorce.** L image démarre sous QEMU avec notre noyau 7.1.10,
  compilé par le gcc et le binutils de l étage 2, et atteint multi-user en
  moins de six secondes. sshd écoute sur 0.0.0.0:22 : ce noyau enregistre
  PF_INET, celui de `boot/` ne le faisait pas.
- **ERPLibre sert dans cette VM.** `/web/login` rend 200, un JSON-RPC
  authentifié lit l ORM, 12 modules sont installés sur PostgreSQL 18.6.
  postgresql et odoo sont des unités systemd activées : après un
  `systemctl poweroff` et un redémarrage, rien n est tapé dans l invité et le
  service répond.
- **Deux images se fabriquent.** `build-image.sh` produit un Arch s390x qui
  amorce seul (zipl), et `build-erplibre-image.sh` le pilote pour en faire une
  image ERPLibre prête : ERPLibre installé, Odoo servi, puis l identité machine
  retirée — clés d hôte, machine-id, journaux. Déployée par le TODO d ERPLibre,
  elle rend 200 sur `/web/login` sans qu on y touche.
- **cloud-init est construit** : trente paquets, et `EL_CLOUD_INIT=1` le met
  dans l image avec ses quatre unités.
- **Étage 3 : 228 paquets sur 231**, et la comparaison est faite : **263
  identiques, 13 différents, aucun contaminé**. Les treize s'expliquent — un
  chroot d'étage 3 plus riche fait produire aux paquets leur doc et leurs
  complétions, deux versions portent une date de construction, cython attend
  une reconstruction. glibc et gcc sont parmi les identiques : la chaîne se
  reproduit. Manquent rust (disque), libaio (source disparue), autoconf-archive
  (miroir en panne).
- **Étage 3 : commencé.** `STAGE_N=3 bash scripts/build-stage2.sh --all` —
  chroot peuplé du seul étage 2, résultat dans `repo3`. Le chroot compile (11
  sur 11) et 18 paquets sont refaits. Il a montré que `repo2` n'était pas fermé —
  six dépendances déclarées y manquaient, **c'est réparé** : les 278 paquets
  s'installent ensemble dans un chroot vide, sans repli. Reste à mener la passe
  des 231 paquets à son terme, puis à comparer l'étage 3 à l'étage 2.

## Les décisions à connaître

**Base processeur : z13, tune z16.** Arch ne nomme aucune base s390x, donc GCC
retombait sur `arch5` = z900, l'an 2000, et tout paquet à intrinsèques
vectoriels échouait. Posée à deux endroits qui répondent à deux questions :
`makepkg.conf` du chroot (comment on compile) et `--with-arch` de gcc (ce que
suppose le compilateur livré). z13 est ce qu'Ubuntu s390x exige déjà.

**`filesystem` livre les liens lib64 sur s390x.** Arch ne les crée que pour
x86_64 ; sans eux, la chaîne s390x crée un **vrai** `/usr/lib64`, ce qui
retourne le libdir par défaut de meson et casse tout pkg-config.

**Documentation : elle cède.** L'`arch-meson` du chroot est enveloppé avec
`--auto-features auto`. Neuf outils de documentation manquent et chacun coûte un
moteur de langage entier (doxygen → LLVM, asciidoctor → Ruby, a2x → Python).
À restaurer à l'étage 3.

**L'étage 2 est reprenable.** Le chroot est reconstruit à chaque passage, donc sa
production y est réinstallée au démarrage — mais **seulement ce que
`stage2.state` déclare encore de confiance**. Retirer un nom du registre est la
façon de dire « ne restaure pas cet artefact ».

## Les cinq formes d'échec

1. **Contamination** — un chemin de l'hôte dans un paquet (multiarch Debian,
   `/usr/local`, `usr/lib64`). Le test ARTEFACT les compte.
2. **Trou de fermeture** — l'étage 1 bâtit sous `--nodeps`, donc un paquet peut
   se construire et rester ininstallable. `help2man` a bloqué une passe entière
   ainsi. Le test RESOLVE est là pour ça.
3. **L'hôte est en retard** — libxslt exige libxml2 ≥ 2.15.1, Ubuntu livre
   2.14.5. Ni contamination ni manque : la mauvaise machine. Ces paquets se
   bâtissent **par** l'étage 2, pas dans l'étage 1, et sont hissés dans
   `STAGE2_FIRST`. Une passe d'étage 1 doit les déclarer en échec.
5. **La source elle-même disparaît** — `libaio` ne se retélécharge plus : le
   404 ne vient pas d'une panne mais d'un amont qui ne génère plus d'archive à
   ce chemin. Le paquet est dans `repo2`, il ne peut plus être refait. Épingler
   protège la reproductibilité ET fige une URL. La réponse est un miroir local
   des sources, que ce portage n'a pas encore.
4. **Un artefact interrompu survit à la passe qui l'a produit** — un tarball du
   noyau arrêté à 54 des 158 Mo, et la passe suivante annonce `-> Found
   linux-7.1.10.tar.xz` puis meurt à l'extraction. Les sommes de contrôle sont
   éteintes ici, parce que les correctifs sont engendrés, donc un fichier court
   EST le fichier. L'erreur de téléchargement est dans un journal, celle
   d'extraction dans le suivant, et elles ne nomment pas la même chose. `xz -t`
   répond en une seconde.

## Pièges qui ont coûté du temps

- **Un garde qui vérifie une chose voisine de ce qu'il veut dire** — cinq fois.
  `test -L` qui échoue ne dit pas « vrai répertoire » : il échoue aussi sur un
  chemin absent. Un `grep -A1 --enable-languages=ada` vérifiait une ancre qu'une
  section antérieure du même hook avait supprimée.
- **La première erreur d'un journal n'est pas la cause.** makepkg poursuit après
  un `.BUILDINFO` manqué : cinq échecs ont été attribués à gpgme alors que la
  ligne fatale, plus bas, était toujours la même.
- **`\s` en Python englobe les retours de ligne.** Une indentation capturée
  contenait un saut de ligne et a inséré un drapeau dans le vide. Travailler sur
  les **lignes**, pas sur les décalages.
- **Un échec ssh n'est pas la preuve qu'un travail distant est fini.** Le lien du
  rebond tombe. Faire imprimer la réponse par la commande distante et la faire
  sortir en 0, exiger plusieurs absences consécutives, ne jamais conclure depuis
  un hôte injoignable.
- **Ne jamais `sed -i` un script qu'un bash est en train de lire.** Un fichier
  de guetteur par lancement.
- **Cinq endroits pour retirer un composant** : tableau `pkgname`, bloc de
  construction, lignes `_pick`, cibles make explicites, et le silencieux — le
  tableau `depends` d'un **autre** sous-paquet, plus les `depends+=` dans
  `package()`.

## Commits

Identité git : reprendre celle des commits existants (`git log -1 --format='%an <%ae>'`),
passée en `-c user.name=... -c user.email=...`. `TZ='America/Montreal'`, message écrit dans un fichier puis `git commit -F`.
Sujet `[TYPE] portée : sujet`, 72 caractères au plus. Corps bilingue : anglais,
`--- FR ---`, français, ~10 lignes par langue. Trailer
`Assisted-by: Claude Opus 5`. **Jamais** d'IA dans `Co-authored-by:`.
Lister les fichiers explicitement — **jamais `git add -A`**.

## Ce qui reste

1. Passe d'étage 2 **avec** les suites de tests, sans `EL_NOCHECK`.
2. Étage 3, puis comparaison étage 3 / étage 2.

   `pkgbuild/<nom>/PKGBUILD` sert aux paquets qu Arch n empaquettera jamais —
   s390-tools est le premier. C est une porte à n ouvrir que pour ça : tout le
   reste vient d Arch et se patche par un crochet.
3. Chaque passe d'étage se termine par un RESOLVE : pacman est prié de dire
   si tout le dépôt s'installe ensemble. C'est ce qui manquait — six trous y
   ont vécu des semaines, un septième est tombé au premier lancement.
4. Ce que le déploiement ne couvre pas : nginx, un service entrant qui ne soit
   pas un `hostfwd`, et le bundle CA engendré à la construction de l'image
   plutôt qu'à la main dans l'invité — `pacman --root` ne lance aucun
   scriptlet, donc l'image part avec `/etc/ca-certificates/extracted` vide et
   tout client TLS échoue sur `error adding trust anchors`.
5. Les addons dans la VM : 127 dépôts se clonent et s'installent dans un
   chroot, rien ne l'a encore fait dans l'invité amorcé.
6. mysqlclient, laissé de côté : poetry ne finit pas sans lui, alors que
   l'installeur Arch d'ERPLibre marque `mariadb-libs` optionnel.
7. Le dépôt est SIGNÉ (`scripts/sign-repo.sh`), et un invité le vérifie si on
   le lui demande : `setup-guest-pacman.sh <hôte:port> --verify`, ou
   `EL_VERIFY_REPO=1` à la construction d'une image. La clé privée vit sous le
   répertoire de travail, jamais dans le dépôt git, et n'a pas de phrase de
   passe — ce qu'elle prouve et ce qu'elle ne prouve pas est écrit dans
   `TODO.md`.
