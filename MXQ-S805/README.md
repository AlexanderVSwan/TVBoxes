Приставка с надписью MXQ, примерно из 2015-2016 годов.
Внутри Amlogic S805, 1G RAM, 8G NAND SDTNRGAMA-008G, Realtek RTL8189ES
На плате написано HD180_v14 2015/12/21
Кодовое имя S805 это  Meson8B


Для экспериментов с приставкой MXQ (Amlogic S805, `m201_N`) использовался следующий образ Armbian Community:

-  Файл `Armbian_community_26.11.0-trunk.62_Onecloud_trixie_current_6.12.28_minimal.img.xz`
-  Платформа в названии  Onecloud
-  Вариант Minimal
-  Источник [Armbian Community Releases](https://github.com/armbian/community/releases)

Именно этот файл записывался на microSD-карты, использовавшиеся в экспериментах с MXQ.

**Важно:** исходная сборка обозначена как `Onecloud`, а не `Aml-s805-mxq`. Не следует считать её специализированным образом для MXQ. Настройки Device Tree и загрузки, описанные далее, относятся к конфигурации, использовавшейся в экспериментах с MXQ.




meson8b-mxq-wifi-pu.dtb
Описывает конфигурацию Wi-Fi-адаптера Realtek RTL8189ES, подключённого по шине SDIO, а также внутренние подтягивающие резисторы на линиях интерфейса SD-карты.

meson8b-mxq-wifi-pu.dts
Текстовый вариант meson8b-mxq-wifi-pu.dtb


Добавил в rc.local что бы исключить переключение частот SoC и растащить прерывания по ядрам.

if [ -d /sys/devices/system/cpu/cpu0/cpufreq ]; then
    echo 1200000 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq
    echo 1200000 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq
    echo performance > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
fi

IRQ_ETH=$(awk -F: '/eth0/ {gsub(/ /, "", $1); print $1}' /proc/interrupts)
IRQ_MMC1=$(awk -F: '/c1108c20\.mmc/ {gsub(/ /, "", $1); print $1}' /proc/interrupts)
IRQ_MMC2=$(awk -F: '/c1108e00\.mmc/ {gsub(/ /, "", $1); print $1}' /proc/interrupts)

[ -n "$IRQ_ETH" ]  && echo 2 > /proc/irq/$IRQ_ETH/smp_affinity
[ -n "$IRQ_MMC1" ] && echo 4 > /proc/irq/$IRQ_MMC1/smp_affinity
[ -n "$IRQ_MMC2" ] && echo 8 > /proc/irq/$IRQ_MMC2/smp_affinity

exit 0

