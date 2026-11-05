#!/usr/bin/env fish
# mode-conservation.fish : bouton dans la barre des tâches pour activer /
# désactiver le mode conservation de la batterie (Lenovo, pilote ideapad_laptop).
#
# Ce que ça installe :
#   - /usr/local/bin/battery-conservation (root), qui n'accepte que on/off/toggle/status
#   - une règle sudoers limitée à ce seul script, pour cliquer sans mot de passe
#   - un service qui remet le mode conservation au démarrage
#   - un lanceur « Basculer mode conservation » épinglé dans la barre
#
# Usage : fish mode-conservation.fish   (sans sudo)

set -g HELPER      /usr/local/bin/battery-conservation
set -g SUDOERS     /etc/sudoers.d/battery-conservation
set -g SERVICE     /etc/systemd/system/conservation-mode.service
set -g USER_TOGGLE "$HOME/.local/bin/battery-conservation-toggle"
set -g DESKTOP_ID  battery-conservation-toggle.desktop
set -g DESKTOP     "$HOME/.local/share/applications/$DESKTOP_ID"
set -g CM_PATH     /sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode
set -g ERRORS      0

function say
    set_color cyan
    echo "▶ $argv"
    set_color normal
end

function ok
    set_color green
    echo "  ✔ $argv"
    set_color normal
end

function warn
    set_color yellow
    echo "  ! $argv"
    set_color normal
end

function fail
    set_color red
    echo "  ✘ $argv"
    set_color normal
    set -g ERRORS (math $ERRORS + 1)
end

function plasma_eval
    busctl --user call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell evaluateScript s "$argv[1]" >/dev/null 2>&1
end

# le script root. charge_types (Long_Life) est l'interface actuelle du noyau,
# conservation_mode est l'ancienne, gardée en secours
function write_helper
    echo '#!/bin/sh
# battery-conservation on|off|toggle|status  (à lancer en root)
CT=$(ls /sys/class/power_supply/BAT*/charge_types 2>/dev/null | head -n 1)
CM=/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode

is_on() {
    if [ -n "$CT" ] && grep -q "\[Long_Life\]" "$CT" 2>/dev/null; then
        return 0
    fi
    if [ -r "$CM" ] && [ "$(cat "$CM" 2>/dev/null)" = "1" ]; then
        return 0
    fi
    return 1
}

state() {
    if is_on; then echo on; else echo off; fi
}

set_mode() {
    if [ "$1" = "on" ]; then ct_val=Long_Life; cm_val=1; else ct_val=Standard; cm_val=0; fi
    if [ -n "$CT" ]; then
        { echo "$ct_val" > "$CT"; } 2>/dev/null
    fi
    if [ "$(state)" != "$1" ] && [ -w "$CM" ]; then
        { echo "$cm_val" > "$CM"; } 2>/dev/null
    fi
}

want=""
case "$1" in
    on|off) want="$1" ;;
    toggle) if is_on; then want=off; else want=on; fi ;;
    status) ;;
    *) echo "usage: battery-conservation on|off|toggle|status" >&2; exit 2 ;;
esac

if [ -n "$want" ]; then set_mode "$want"; fi
now=$(state)
echo "$now"
[ -z "$want" ] || [ "$now" = "$want" ]' >$argv[1]
end

# ce que lance le bouton
function write_toggle
    echo '#!/bin/sh
if now=$(sudo -n /usr/local/bin/battery-conservation toggle); then
    if [ "$now" = "on" ]; then
        msg="Activé : la charge s’arrête, le PC tourne sur le secteur."
    else
        msg="Désactivé : la batterie se charge normalement."
    fi
    notify-send -i preferences-system-power-management "Mode conservation" "$msg"
else
    notify-send -u critical -i dialog-error "Mode conservation" "Échec du changement (sudo ou pilote)."
    exit 1
fi' >$argv[1]
end

say "Vérification"

if test (id -u) -eq 0
    fail "Lance-le sans sudo, il le demandera"
    exit 1
end
if not string match -q '*KDE*' -- "$XDG_CURRENT_DESKTOP"
    fail "Pas une session KDE"
    exit 1
end
for cmd in sudo visudo systemctl busctl
    if command -q $cmd
        ok "$cmd trouvé"
    else
        fail "Commande manquante : $cmd"
    end
end
test $ERRORS -gt 0; and exit 1

if not command -q notify-send
    warn "notify-send absent : pas de notification (sudo pacman -S libnotify)"
end

set -l ct_files /sys/class/power_supply/BAT*/charge_types
if test (count $ct_files) -gt 0; and test -e "$ct_files[1]"
    ok "charge_types trouvé : $ct_files[1]"
else if test -e $CM_PATH
    warn "pas de charge_types, on passe par l'ancien conservation_mode"
else
    fail "Ni charge_types ni conservation_mode : pas de mode conservation sur ce PC"
    exit 1
end

say "Script root et règle sudo"

set -l tmp_helper (mktemp)
write_helper $tmp_helper
if not sh -n $tmp_helper
    fail "Script root généré invalide"
    rm -f $tmp_helper
    exit 1
end
sudo install -m 755 -o root -g root $tmp_helper $HELPER
and ok "$HELPER installé"
or fail "Échec de l'installation de $HELPER"
rm -f $tmp_helper
test $ERRORS -gt 0; and exit 1

set -l me (id -un)
set -l tmp_sudo (mktemp)
printf '%s\n' \
    '# seulement le script du mode conservation, sans mot de passe' \
    "$me ALL=(root) NOPASSWD: $HELPER on, $HELPER off, $HELPER toggle, $HELPER status" \
    >$tmp_sudo
# on vérifie avec visudo avant d'installer, une règle cassée bloquerait sudo
if sudo visudo -cf $tmp_sudo >/dev/null
    sudo install -m 440 -o root -g root $tmp_sudo $SUDOERS
    and ok "Règle sudo installée ($SUDOERS)"
    or fail "Échec de l'installation de la règle sudo"
else
    fail "Règle sudo invalide, rien installé"
end
rm -f $tmp_sudo
test $ERRORS -gt 0; and exit 1

say "Service de démarrage"

printf '%s\n' \
    '[Unit]' \
    'Description=Lenovo battery conservation mode' \
    '' \
    '[Service]' \
    'Type=oneshot' \
    "ExecStart=$HELPER on" \
    '' \
    '[Install]' \
    'WantedBy=multi-user.target' \
    | sudo tee $SERVICE >/dev/null
sudo systemctl daemon-reload
sudo systemctl enable conservation-mode.service >/dev/null 2>&1
if sudo systemctl restart conservation-mode.service
    ok "Mode conservation activé à chaque démarrage"
else
    fail "Le service échoue : journalctl -u conservation-mode.service -n 20"
end

say "Bouton"

mkdir -p $HOME/.local/bin $HOME/.local/share/applications
write_toggle $USER_TOGGLE
chmod +x $USER_TOGGLE
if sh -n $USER_TOGGLE
    ok "$USER_TOGGLE créé"
else
    fail "$USER_TOGGLE invalide"
end

# première icône qui existe dans le thème
set -l icon battery
for candidate in preferences-system-power-management battery-060 battery
    if test -n "$(find /usr/share/icons $HOME/.local/share/icons -name "$candidate.*" 2>/dev/null | head -n 1)"
        set icon $candidate
        break
    end
end

printf '%s\n' \
    '[Desktop Entry]' \
    'Type=Application' \
    'Name=Basculer mode conservation' \
    'Comment=Active ou désactive la limite de charge de la batterie' \
    "Exec=$USER_TOGGLE" \
    "Icon=$icon" \
    'Terminal=false' \
    'Categories=Utility;' \
    'StartupNotify=false' \
    >$DESKTOP
ok "Lanceur créé (icône : $icon)"

if command -q kbuildsycoca6
    kbuildsycoca6 >/dev/null 2>&1
end

say "Épinglage dans la barre"

set -l pin_js 'var wanted = "applications:battery-conservation-toggle.desktop"; var ps = panels(); for (var i = 0; i < ps.length; i++) { var ws = ps[i].widgets(); for (var j = 0; j < ws.length; j++) { var w = ws[j]; if (w.type == "org.kde.plasma.icontasks" || w.type == "org.kde.plasma.taskmanager") { w.currentConfigGroup = ["General"]; var cur = String(w.readConfig("launchers", "")); if (cur != "" && cur.indexOf(wanted) < 0) { w.writeConfig("launchers", cur + "," + wanted); w.reloadConfig(); } } } }'

if plasma_eval "$pin_js"
    sleep 3
    if grep -q "battery-conservation-toggle" $HOME/.config/plasma-org.kde.plasma.desktop-appletsrc 2>/dev/null
        ok "Épinglé dans la barre des tâches"
    else
        warn "Pas confirmé : clic droit sur le lanceur dans le menu > Épingler au gestionnaire de tâches"
    end
else
    warn "Épinglage auto impossible, à faire à la main depuis le menu"
end

say "Test"

set -l state (sudo -n $HELPER status 2>&1)
if test "$state" = on -o "$state" = off
    ok "Mode conservation actuellement : $state"
else
    fail "sudo sans mot de passe ne marche pas : $state"
end

echo
if test $ERRORS -eq 0
    set_color green
    echo "Terminé sans erreur."
    set_color normal
    echo "  • Bouton : « Basculer mode conservation » dans la barre"
    echo "  • Raccourci : Paramètres > Clavier > Raccourcis > Applications > Basculer mode conservation"
    echo "  • Terminal : sudo battery-conservation status"
else
    set_color red
    echo "Terminé avec $ERRORS erreur(s), voir les lignes ✘."
    set_color normal
    exit 1
end
