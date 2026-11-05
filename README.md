# batterie-lunar-lake

Script de réglages batterie pour un portable Intel Lunar Lake (Core Ultra 200V) sous CachyOS + KDE Plasma 6, et une commande `conso` pour voir la consommation en direct.

Je l'ai écrit parce que mon Yoga 7 2-in-1 (Core Ultra 7 258V) tenait nettement moins longtemps que sous Windows.

## Le problème trouvé

Sur les nouvelles installs, l'outil de détection matérielle de CachyOS (`chwd`) installe **intel-lpmd**. Sa config Lunar Lake (`intel_lpmd_config_F6_M189.xml`) le laisse actif même dans le profil *Économie d'énergie*, et il impose alors au CPU un EPP entre 64 et 192 selon la charge, alors que ce profil devrait mettre 255 (`power`, le plus économe). Résultat : en « économie d'énergie », le processeur se comporte presque comme en équilibré.

Le script met `PowersaverDef` à `-1` : intel-lpmd ne fait plus rien en Économie d'énergie mais continue de travailler en Équilibré. L'ancienne config est sauvegardée à côté (`.avant-batterie`).

## Ce que fait `batterie.sh`

1. corrige intel-lpmd (s'il est installé) ;
2. profils automatiques dans PowerDevil : branché → Équilibré, sur batterie → Économie d'énergie ;
3. `powertop --auto-tune` à chaque démarrage, sauf pour les souris/claviers USB (sinon ils laguent) ;
4. synchronisation adaptative de l'écran sur *Automatique* (en *Toujours*, elle empêche le PSR) ;
5. installe la fonction fish `conso` ;
6. affiche un bilan : profil, EPP, intel-lpmd, PSR, économie Wi-Fi.

On peut le relancer sans risque, il saute ce qui est déjà fait. À relancer après une mise à jour d'intel-lpmd, qui peut remettre la config d'origine.

## Utilisation

```bash
git clone https://github.com/glime32/batterie-lunar-lake
cd batterie-lunar-lake
bash batterie.sh      # sans sudo, il le demande lui-même
```

Puis, sur batterie :

```
❯ conso
Santé : 97 % (68,1 Wh sur 70,0 Wh)
Mesure toutes les 2 s, Ctrl+C pour arrêter

🔋 4,8 W  ·  moyenne 5,1 W  ·  reste ≈ 10 h 15  ·  CPU : power
```

`conso` gère les batteries qui exposent `power_now`/`energy_now` comme celles qui donnent `current_now`/`voltage_now`.

## Bouton « mode conservation »

`mode-conservation.fish` ajoute dans la barre des tâches un bouton qui active ou coupe le mode conservation des portables Lenovo (la charge s'arrête vers 60 %, ce qui ménage la batterie quand le PC reste branché).

```bash
fish mode-conservation.fish   # sans sudo
```

Il installe :

- `/usr/local/bin/battery-conservation` (root), qui n'accepte que `on`, `off`, `toggle` et `status` ;
- une règle sudoers limitée à ce seul script, pour cliquer sans mot de passe (vérifiée avec `visudo` avant d'être installée) ;
- un service qui remet le mode conservation à chaque démarrage ;
- le lanceur « Basculer mode conservation », épinglé dans la barre, avec une notification à chaque changement.

Le script passe par `charge_types` (`Long_Life` / `Standard`), l'interface actuelle du noyau, et garde l'ancien `conservation_mode` d'ideapad_acpi en secours.

Branché avec le mode actif, le PC tourne sur le secteur sans charger : la batterie est maintenue, pas vidée. Pour vérifier : `upower -i (upower -e | grep BAT)` doit montrer un `energy-rate` proche de 0 W. Penser à le couper avant un déplacement pour avoir 100 %.

Si tu préfères que ton dernier choix reste après un redémarrage : `sudo systemctl disable conservation-mode.service`.

## Remarques

- Fait pour CachyOS (pacman, `cachyos-keyring`) et KDE Plasma 6 (`kwriteconfig6`, `kscreen-doctor`). Sur une autre distro il faudra adapter l'installation de powertop.
- Si le PC semble trop lent sur batterie, repasser en Équilibré depuis la zone de notification : intel-lpmd reprend la main.
