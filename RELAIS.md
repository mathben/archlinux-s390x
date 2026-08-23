# Arch Linux sur s390x — état du portage

Objectif : **ERPLibre tourne sur Arch Linux s390x.** Terminé quand ERPLibre
fonctionne, pas quand les paquets compilent.

## Où est quoi

| | |
|---|---|
| Machine | la VM de developpement s390x, Ubuntu, joignable par un rebond ssh |
| Dépôt du portage | `~/git/archlinux-s390x` — **72 commits, aucun distant** |
| Espace de travail | `~/work/arch-s390x` |
| Dépôt étage 1 | `~/work/arch-s390x/repo/s390x` |
| Dépôt étage 2 | `~/work/arch-s390x/repo2/s390x` |
| Chroot étage 2 | `~/work/arch-s390x/rootfs-stage2` |
| Registres | `stage1.state`, `stage2.state` |

**Ne pas toucher** : `/var/lib/libvirt` (VM d'autres travaux). Le `/tmp` de
cette machine est partagé **et** en tmpfs — utiliser un sous-répertoire à soi.

## Comment on lance

```bash
cd ~/git/archlinux-s390x
bash scripts/build-stage1.sh                 # toute la liste
bash scripts/build-stage1.sh gperf rsync     # à la demande, écrase le registre
EL_NOCHECK=1 bash scripts/build-stage2.sh --all
bash scripts/build-stage2.sh libxml2         # un paquet
bash scripts/test-chroot.sh                  # RESOLVE / ARTEFACT / SONAME / RUN
```

Toujours en arrière-plan, la sortie dans un fichier :

```bash
setsid nohup bash scripts/build-stage2.sh --all > ~/work/arch-s390x/out.txt 2>&1 < /dev/null &
```

`EL_STALL_MIN` (défaut 45) tue une construction muette ; `EL_NOCHECK=1` saute
les suites de tests, à réserver à la première passe.

## Où on en est

- **Étage 1 : 180 paquets**, `RESOLVE ok` — la fermeture du chroot résout à
  **148 paquets** avec `--nodeps` éteint. `ARTEFACT ok`, `RUN ok`.
- **Étage 2** : `glibc`, `texinfo`, `libxml2`, `linux-api-headers`, `pkgconf` et
  ~75 autres reconstruits dans le chroot. Passe complète en cours.
- Test de fumée du chroot : **11 ok, 0 échec, 0 dérive connue**.
- **Étage 3 : pas commencé.** Auto-hébergement quand l'étage 3 reproduit
  l'étage 2.
- **ERPLibre : pas commencé.** 18 paquets et leur fermeture, puis ERPLibre.

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

## Les trois formes d'échec

1. **Contamination** — un chemin de l'hôte dans un paquet (multiarch Debian,
   `/usr/local`, `usr/lib64`). Le test ARTEFACT les compte.
2. **Trou de fermeture** — l'étage 1 bâtit sous `--nodeps`, donc un paquet peut
   se construire et rester ininstallable. `help2man` a bloqué une passe entière
   ainsi. Le test RESOLVE est là pour ça.
3. **L'hôte est en retard** — libxslt exige libxml2 ≥ 2.15.1, Ubuntu livre
   2.14.5. Ni contamination ni manque : la mauvaise machine. Ces paquets se
   bâtissent **par** l'étage 2, pas dans l'étage 1, et sont hissés dans
   `STAGE2_FIRST`. Une passe d'étage 1 doit les déclarer en échec.

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

1. Finir la passe d'étage 2 ; les échecs restants sont à classer par la
   **dernière** erreur de chaque journal.
2. Rebâtir `pacman` à l'étage 2 : celui de l'étage 1 réclame `libgpgme.so.11`
   (hôte 1.x) quand notre gpgme livre `.45`. Inoffensif pendant la
   construction, fatal sur la cible.
3. Passe d'étage 2 **avec** les suites de tests, sans `EL_NOCHECK`.
4. Étage 3, puis comparaison étage 3 / étage 2.
5. Les 18 paquets d'ERPLibre et leur fermeture. Puis ERPLibre.
