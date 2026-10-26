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

# Маски 4 позиций цифр из таблицы 0xffffffc0094f59c8:
# Позиция 0 (1-я цифра) = 0x80
# Позиция 1 (2-я цифра) = 0x40
# Позиция 2 (3-я цифра) = 0x20
# Позиция 3 (4-я цифра) = 0x10
POS_MASKS=(0x80 0x40 0x20 0x10)

# Кодировка символов из get_dispaly_data (биты 0..6 = байты 0,2,4,6,8,10,12)
declare -A CHAR_MAP=(
    ["0"]=0x3F ["1"]=0x06 ["2"]=0x5B ["3"]=0x4F ["4"]=0x66
    ["5"]=0x6D ["6"]=0x7D ["7"]=0x07 ["8"]=0x7F ["9"]=0x6F
    ["A"]=0x77 ["L"]=0x38 ["d"]=0x5E ["o"]=0x5C [" "]=0x00 ["-"]=0x40
)

# Функция вывода: принимает 4 символа и флаги иконок (1=вкл, 0=выкл)
# Иконки (бит 0x08 в четных байтах):
# buf[0] (смещение 0)  = USB
# buf[1] (смещение 2)  = CARD
# buf[2] (смещение 4)  = AM
# buf[3] (смещение 6)  = PM
# buf[4] (смещение 8)  = COLON (:)
# buf[5] (смещение 10) = WIFI
# buf[6] (смещение 12) = LAN (проводная сеть)
update_display() {
    local text="$1"
    local usb="${2:-0}"
    local card="${3:-0}"
    local am="${4:-0}"
    local pm="${5:-0}"
    local colon="${6:-0}"
    local wifi="${7:-0}"
    local lan="${8:-0}"

    local buf=(0 0 0 0 0 0 0)
    local pos ch seg_mask pos_bit seg

    # Формируем цифры (алгоритм get_dispaly_data)
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

    # Добавляем иконки (бит 3 = 0x08, как в dig_led_tm1628_ioctl)
    [[ "$usb" == "1" ]]   && buf[0]=$(( buf[0] | 0x08 ))
    [[ "$card" == "1" ]]  && buf[1]=$(( buf[1] | 0x08 ))
    [[ "$am" == "1" ]]    && buf[2]=$(( buf[2] | 0x08 ))
    [[ "$pm" == "1" ]]    && buf[3]=$(( buf[3] | 0x08 ))
    [[ "$colon" == "1" ]] && buf[4]=$(( buf[4] | 0x08 ))
    [[ "$wifi" == "1" ]]  && buf[5]=$(( buf[5] | 0x08 ))
    [[ "$lan" == "1" ]]   && buf[6]=$(( buf[6] | 0x08 ))

    # Отправка в TM1628 точно как в рабочем тесте
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

echo "Тест 1: Выводим 12:34 + двоеточие + Wi-Fi..."
# Параметры: текст, USB, CARD, AM, PM, COLON, WIFI, LAN
update_display "1234" 0 0 0 0 1 1 0

read -p "Нажмите Enter, чтобы вывести текущее время и включить LAN..."

NOW=$(date +"%H%M")
update_display "$NOW" 0 0 0 0 1 0 1
echo "Выведено время $NOW и значок проводной сети!"

