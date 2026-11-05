# conso : affiche la conso de la batterie en direct
function conso --description 'Consommation de la batterie en direct'
    set -l bat
    for b in /sys/class/power_supply/BAT*
        set bat $b
        break
    end
    if test -z "$bat"
        echo "Pas de batterie."
        return 1
    end

    # santé = capacité actuelle / capacité neuve
    if test -r $bat/energy_full; and test -r $bat/energy_full_design
        read -l plein < $bat/energy_full
        read -l origine < $bat/energy_full_design
        set -l sante (math "round(100 * $plein / $origine)")
        set -l wh (math -s1 "$plein / 1000000" | string replace . ,)
        set -l wh0 (math -s1 "$origine / 1000000" | string replace . ,)
        echo "Santé : $sante % ($wh Wh sur $wh0 Wh)"
    end
    echo "Mesure toutes les 2 s, Ctrl+C pour arrêter"
    echo

    set -l somme 0
    set -l n 0
    while true
        read -l etat < $bat/status
        if test "$etat" != Discharging
            set somme 0
            set n 0
            printf '\r\x1b[K🔌 Sur secteur, débranche pour mesurer.'
            sleep 2
            continue
        end

        # puissance en µW (certaines batteries donnent courant + tension à la place)
        set -l p 0
        if test -r $bat/power_now
            read p < $bat/power_now
        else if test -r $bat/current_now; and test -r $bat/voltage_now
            read -l i < $bat/current_now
            read -l v < $bat/voltage_now
            set p (math "round($i * $v / 1000000)")
        end

        # énergie restante en µWh
        set -l e 0
        if test -r $bat/energy_now
            read e < $bat/energy_now
        else if test -r $bat/charge_now; and test -r $bat/voltage_now
            read -l c < $bat/charge_now
            read -l v < $bat/voltage_now
            set e (math "round($c * $v / 1000000)")
        end

        # juste après le débranchement le noyau renvoie souvent 0
        if test "$p" -le 0
            sleep 2
            continue
        end

        set somme (math "$somme + $p")
        set n (math "$n + 1")
        set -l moy (math "round($somme / $n)")
        set -l w (math -s1 "$p / 1000000" | string replace . ,)
        set -l wmoy (math -s1 "$moy / 1000000" | string replace . ,)
        set -l minutes (math "round(60 * $e / $moy)")
        set -l h (math "floor($minutes / 60)")
        set -l m (math "$minutes % 60")

        set -l cpu '?'
        if test -r /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference
            read cpu < /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference
        end

        printf '\r\x1b[K🔋 %s W  ·  moyenne %s W  ·  reste ≈ %s h %02d  ·  CPU : %s' $w $wmoy $h $m $cpu
        sleep 2
    end
end
