#!/bin/bash
set -e

GPIO=/sys/class/gpio
CLK=146
DIO=129
STB=142

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

LEVELS=(
    "0x88 (Уровень 1/8 - минимум, 1/16)"
    "0x89 (Уровень 2/8 - 2/16)"
    "0x8A (Уровень 3/8 - 4/16)"
    "0x8B (Уровень 4/8 - 10/16)"
    "0x8C (Уровень 5/8 - 11/16)"
    "0x8D (Уровень 6/8 - 12/16)"
    "0x8E (Уровень 7/8 - 13/16)"
    "0x8F (Уровень 8/8 - максимум, 14/16)"
)

echo "=== Тест регулировки яркости TM1628 ==="
echo "Сначала проверим плавный перебор от минимума к максимуму в автоматическом режиме..."

for round in 1 2; do
    # От минимума к максимуму
    for ((cmd=0x88; cmd<=0x8F; cmd++)); do
        send_cmd "$cmd"
        sleep 0.25
    done
    # И обратно к минимуму
    for ((cmd=0x8F; cmd>=0x88; cmd--)); do
        send_cmd "$cmd"
        sleep 0.25
    done
done

echo -e "\nТеперь пошаговый режим (по нажатию Enter):"
for ((i=0; i<8; i++)); do
    cmd=$(( 0x88 + i ))
    send_cmd "$cmd"
    echo "---> Включен режим: ${LEVELS[$i]}"
    read -p "Нажмите Enter для следующего уровня..."
done

echo "---> Тест команды 0x80 (аппаратное выключение экрана с сохранением памяти RAM)..."
send_cmd 0x80
read -p "Экран погас! Нажмите Enter, чтобы мгновенно вернуть яркость..."

# Возвращаем комфортный уровень (или максимум 0x8F)
send_cmd 0x8F
echo "Готово! Возвращена максимальная яркость (0x8F)."

