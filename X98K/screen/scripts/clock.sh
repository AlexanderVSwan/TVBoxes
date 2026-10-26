#!/bin/bash
set -e

GPIO=/sys/class/gpio
CLK=146
DIO=129
STB=142

# Инициализация GPIO
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

# Маски позиций (знакоместа 0, 1, 2, 3)
POS_MASKS=(0x80 0x40 0x20 0x10)

# Классические 7-сегментные маски (бит 0 = seg_a, бит 1 = seg_b, ..., бит 6 = seg_g)
declare -A CHAR_MAP=(
    ["0"]=0x3F ["1"]=0x06 ["2"]=0x5B ["3"]=0x4F ["4"]=0x66
    ["5"]=0x6D ["6"]=0x7D ["7"]=0x07 ["8"]=0x7F ["9"]=0x6F
    ["A"]=0x77 ["a"]=0x77 ["L"]=0x38 ["l"]=0x38 ["d"]=0x5E
    ["o"]=0x5C ["O"]=0x3F [" "]=0x00 ["-"]=0x40
)

# Функция отрисовки строки из 4 символов и двоеточия (1=вкл, 0=выкл)
display_text() {
    local text="$1"
    local colon="${2:-0}"
    
    # 7 байтов буфера для сегментов a, b, c, d, e, f, g
    local buf=(0 0 0 0 0 0 0)
    
    for ((pos=0; pos<4; pos++)); do
        local ch="${text:$pos:1}"
        local seg_mask=${CHAR_MAP[$ch]:-0x00}
        local pos_bit=${POS_MASKS[$pos]}
        
        for ((seg=0; seg<7; seg++)); do
            if (( (seg_mask >> seg) & 1 )); then
                buf[$seg]=$(( buf[$seg] | pos_bit ))
            fi
        done
    done

    # Двоеточие находится в байте сегмента 'e' (индекс 4, адрес 0xC8), бит 3 (0x08)
    if [[ "$colon" == "1" ]]; then
        buf[4]=$(( buf[4] | 0x08 ))
    fi

    # Передача буфера в TM1628 (точно как в tm1628_display_new)
    send_cmd 0x03
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

# Тест: выведем текущее время ЧЧММ с включенным двоеточием
TIME_STR=$(date +"%H%M")
echo "Выводим на дисплей время: ${TIME_STR:0:2}:${TIME_STR:2:2}"
display_text "$TIME_STR" 1

