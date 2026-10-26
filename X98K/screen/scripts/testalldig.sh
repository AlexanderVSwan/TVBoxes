#!/bin/bash
set -e

GPIO=/sys/class/gpio
CLK=146
DIO=129
STB=142

for n in "$CLK" "$DIO" "$STB"; do
    if [ ! -d "$GPIO/gpio$n" ]; then
        echo "$n" > "$GPIO/export"
        sleep 0.1
    fi
    echo out > "$GPIO/gpio$n/direction"
done

clk() { echo "$1" > "$GPIO/gpio$CLK/value"; }
dio() { echo "$1" > "$GPIO/gpio$DIO/value"; }
stb() { echo "$1" > "$GPIO/gpio$STB/value"; }

send_byte() {
    local b=$1 i
    for ((i=0; i<8; i++)); do
        clk 0
        dio $(( (b >> i) & 1 ))
        clk 1
    done
}

send_cmd() {
    stb 0
    send_byte "$1"
    stb 1
}

# Маски 4 позиций цифр (знакоместа 1..4)
POS_MASKS=(0x80 0x40 0x20 0x10)

# Полная таблица символов (0-9 и специальные буквы из ядра + дополнительные полезные)
declare -A CHAR_MAP=(
    ["0"]=0x3F ["1"]=0x06 ["2"]=0x5B ["3"]=0x4F ["4"]=0x66
    ["5"]=0x6D ["6"]=0x7D ["7"]=0x07 ["8"]=0x7F ["9"]=0x6F
    ["A"]=0x77 ["b"]=0x7C ["C"]=0x39 ["d"]=0x5E ["E"]=0x79
    ["F"]=0x71 ["H"]=0x76 ["L"]=0x38 ["o"]=0x5C ["P"]=0x73
    ["U"]=0x3E ["-"]=0x40 ["_"]=0x08 [" "]=0x00
)

update_display() {
    local text="$1"
    local icon_idx="${2:--1}" # Индекс иконки от 0 до 6 (-1 = все выключены)

    local buf=(0 0 0 0 0 0 0)
    local pos ch seg_mask pos_bit seg

    # Формируем 4 знакоместа
    for ((pos=0; pos<4; pos++)); do
        ch="${text:$pos:1}"
        seg_mask=${CHAR_MAP[$ch]:-0x00}
        pos_bit=${POS_MASKS[$pos]}

        for ((seg=0; seg<7; seg++)); do
            if (( (seg_mask >> seg) & 1 )); then
                buf[$seg]=$(( buf[$seg] | pos_bit ))
            fi
        done
    done

    # Включаем выбранную иконку (бит 0x08), если задана
    if (( icon_idx >= 0 && icon_idx < 7 )); then
        buf[$icon_idx]=$(( buf[$icon_idx] | 0x08 ))
    fi

    # Отправка в TM1628
    send_cmd 0x40
    stb 0
    send_byte 0xC0
    for ((seg=0; seg<7; seg++)); do
        send_byte "${buf[$seg]}"
        send_byte 0x00
    done
    stb 1
    send_cmd 0x8F
}

ICON_NAMES=("USB" "CARD" "AM" "PM" "Двоеточие (:)" "Wi-Fi" "LAN (Сеть)")

echo "=== Тест всех цифр (0000 - 9999) и букв во всех позициях ==="

# 1. Прогон всех цифр от 0 до 9
for d in 0 1 2 3 4 5 6 7 8 9; do
    icon_num=$(( d % 7 ))
    echo "На экране: ${d}${d}${d}${d} | Включена иконка: ${ICON_NAMES[$icon_num]}"
    update_display "${d}${d}${d}${d}" "$icon_num"
    read -p "Нажмите Enter для следующей цифры..."
done

# 2. Прогон букв из ядра (ALdo) и полезных слов (boot, Load, Err, Good)
WORDS=("AAAA" "LLLL" "dddd" "oooo" "LPAd" "CHAr" "----")
echo -e "\n=== Тест букв и комбинаций ==="
for w in "AAAA" "LLLL" "dddd" "oooo" "LoAd" "FEEd" "----"; do
    echo "На экране: $w"
    update_display "$w" 4  # вместе с двоеточием
    read -p "Нажмите Enter для продолжения..."
done

# В конце оставляем текущее время
NOW=$(date +"%H%M")
update_display "$NOW" 4
echo "Тест завершен! На экране оставлено текущее время: ${NOW:0:2}:${NOW:2:2}"

