#!/usr/bin/env bash
# batterie.sh - réglages batterie pour mon Yoga 7 2-in-1 (Core Ultra 7 258V)
# sous CachyOS + KDE Plasma 6.
#
# Usage : bash batterie.sh   (sans sudo, il le demande lui-même)
# On peut le relancer autant qu'on veut, il saute ce qui est déjà fait.

VERT=$'\e[32m'; JAUNE=$'\e[33m'; CYAN=$'\e[36m'; VIOLET=$'\e[1;35m'; RAZ=$'\e[0m'
ok()     { printf '  %s✔%s %s\n' "$VERT" "$RAZ" "$*"; }
info()   { printf '  %s•%s %s\n' "$CYAN" "$RAZ" "$*"; }
alerte() { printf '  %s!%s %s\n' "$JAUNE" "$RAZ" "$*"; }
titre()  { printf '\n%s== %s ==%s\n' "$VIOLET" "$*" "$RAZ"; }

if [ "$(id -u)" -eq 0 ]; then
    echo "Lance-le sans sudo, il demandera le mot de passe."
    exit 1
fi

echo "Optimisation de la batterie (mot de passe demandé une fois)."
sudo -v || exit 1


titre "1/5  intel-lpmd"
# chwd installe intel-lpmd sur les Intel récents. Sur Lunar Lake (F6_M189)
# la config CachyOS le laisse en mode auto même en Économie d'énergie, et il
# force alors un EPP entre 64 et 192 au lieu de 255 ("power").
# Avec PowersaverDef=-1 il ne fait plus rien dans ce profil, mais reste
# actif en Équilibré.
LPMD_CFG=/etc/intel_lpmd/intel_lpmd_config_F6_M189.xml
LPMD_SAUVEGARDE="$LPMD_CFG.avant-batterie"
if [ ! -f "$LPMD_CFG" ]; then
    info "intel-lpmd pas installé, rien à faire."
elif grep -q '<PowersaverDef>-1</PowersaverDef>' "$LPMD_CFG"; then
    ok "Déjà fait : intel-lpmd ne touche plus au CPU en Économie d'énergie."
else
    [ -f "$LPMD_SAUVEGARDE" ] || sudo cp "$LPMD_CFG" "$LPMD_SAUVEGARDE"
    sudo sed -i 's|<PowersaverDef>[^<]*</PowersaverDef>|<PowersaverDef>-1</PowersaverDef>|' "$LPMD_CFG"
    if grep -q '<PowersaverDef>-1</PowersaverDef>' "$LPMD_CFG"; then
        if systemctl is-active --quiet intel_lpmd.service; then
            sudo systemctl restart intel_lpmd.service
        fi
        ok "intel-lpmd coupé en Économie d'énergie (toujours actif en Équilibré)."
        info "Ancienne config : $LPMD_SAUVEGARDE"
    else
        alerte "Config au format inattendu, rien changé. Regarde : cat $LPMD_CFG"
    fi
fi


titre "2/5  Profil d'énergie automatique"
# secteur -> Équilibré, batterie (ou batterie faible) -> Économie d'énergie
kwriteconfig6 --file powerdevilrc --group AC         --group Performance --key PowerProfile balanced
kwriteconfig6 --file powerdevilrc --group Battery    --group Performance --key PowerProfile power-saver
kwriteconfig6 --file powerdevilrc --group LowBattery --group Performance --key PowerProfile power-saver
# PowerDevil relit sa config ; si l'appel D-Bus échoue on le relance
if ! dbus-send --session --print-reply --dest=org.kde.Solid.PowerManagement \
        /org/kde/Solid/PowerManagement org.kde.Solid.PowerManagement.reparseConfiguration \
        >/dev/null 2>&1; then
    systemctl --user restart plasma-powerdevil.service 2>/dev/null
fi
ok "Débranché -> Économie d'énergie, branché -> Équilibré."


titre "3/5  powertop"
if [ -f /etc/systemd/system/powertop-tune.service ]; then
    if systemctl is-enabled --quiet powertop-tune.service; then
        ok "Déjà en place : powertop --auto-tune au démarrage."
    else
        alerte "powertop-tune.service existe mais est désactivé, je n'y touche pas."
    fi
else
    if ! command -v powertop >/dev/null 2>&1; then
        info "Installation de powertop..."
        sudo pacman -Sy --needed --noconfirm archlinux-keyring cachyos-keyring
        sudo pacman -Syu --needed powertop
    fi
    if command -v powertop >/dev/null 2>&1; then
        sudo tee /usr/local/bin/powertop-tune.sh >/dev/null <<'EOF'
#!/bin/sh
powertop --auto-tune
# auto-tune met aussi en veille les souris/claviers USB, ce qui fait laguer :
# on les remet toujours actifs
for d in /sys/bus/usb/drivers/usbhid/*:*; do
    [ -e "$d" ] || continue
    dev=$(basename "$d" | cut -d: -f1)
    echo on > "/sys/bus/usb/devices/$dev/power/control" 2>/dev/null
done
EOF
        sudo chmod +x /usr/local/bin/powertop-tune.sh
        sudo tee /etc/systemd/system/powertop-tune.service >/dev/null <<'EOF'
[Unit]
Description=PowerTOP auto-tune (sauf souris/claviers USB)
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/powertop-tune.sh

[Install]
WantedBy=multi-user.target
EOF
        sudo systemctl daemon-reload
        sudo systemctl enable --now powertop-tune.service
        ok "powertop auto-tune appliqué (maintenant et à chaque démarrage)."
    else
        alerte "powertop n'a pas pu être installé, voir l'erreur de pacman au-dessus."
    fi
fi


titre "4/5  Écran"
# VRR sur "Toujours" empêche le PSR (l'écran qui se rafraîchit tout seul
# quand l'image ne bouge pas). "Automatique" = VRR seulement en plein écran.
ECRAN=$(kscreen-doctor -o 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -oE 'eDP-[0-9]+' | head -n1)
if [ -n "$ECRAN" ] && kscreen-doctor "output.$ECRAN.vrrpolicy.automatic" >/dev/null 2>&1; then
    ok "Sync adaptative sur Automatique ($ECRAN)."
else
    alerte "À faire à la main : Paramètres > Affichage > Synchronisation adaptative > Automatique."
fi


titre "5/5  Commande conso"
mkdir -p "$HOME/.config/fish/functions"
cp "$(dirname "$0")/conso.fish" "$HOME/.config/fish/functions/conso.fish" 2>/dev/null \
    && ok "Installée : tape conso dans un terminal (Ctrl+C pour quitter)." \
    || alerte "conso.fish introuvable à côté du script."


titre "Bilan"
if command -v powerprofilesctl >/dev/null 2>&1; then
    info "Profil actuel : $(powerprofilesctl get 2>/dev/null)"
fi

EPP=$(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null)
[ -n "$EPP" ] && info "EPP actuel : $EPP (sur batterie ça doit être power)"

if systemctl is-active --quiet intel_lpmd.service 2>/dev/null; then
    info "intel-lpmd : actif (seulement en Équilibré maintenant)."
else
    info "intel-lpmd : inactif."
fi

PSR=$(sudo sh -c 'cat /sys/kernel/debug/dri/*/i915_edp_psr_status /sys/kernel/debug/dri/*/eDP-*/i915_psr_status' 2>/dev/null \
      | grep -i -m1 'mode')
if [ -z "$PSR" ]; then
    info "PSR : impossible à lire, pas grave."
elif printf '%s' "$PSR" | grep -qi 'disabled'; then
    alerte "PSR désactivé : $PSR"
else
    ok "PSR actif : ${PSR#*: }"
fi

WIFI=$(for d in /sys/class/net/*/wireless; do [ -e "$d" ] && basename "$(dirname "$d")"; done | head -n1)
if [ -n "$WIFI" ] && command -v iw >/dev/null 2>&1; then
    info "Économie Wi-Fi ($WIFI) : $(iw dev "$WIFI" get power_save 2>/dev/null | sed 's/.*: //')"
fi

echo
printf '%sFini.%s Pour mesurer : débranche, attends 2 min, puis lance %sconso%s\n\n' \
    "$VERT" "$RAZ" "$VIOLET" "$RAZ"
