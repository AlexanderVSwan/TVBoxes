# Wi-Fi Access Point — X98K (RK3528)

Настройка X98K под управлением Armbian в качестве беспроводной точки доступа Wi-Fi с раздачей интернета через Ethernet.

## Аппаратная платформа

- Устройство: X98K
- SoC: Rockchip RK3528
- Wi-Fi: AIC8800
- Беспроводной интерфейс: `wlan0`
- Проводной интерфейс: `end0`
- Драйвер Wi-Fi: `nl80211`

## Текущая конфигурация

| Параметр | Значение |
|---|---|
| SSID | `NFQUEUE_300` |
| Диапазон | 2,4 ГГц |
| Канал | 13 |
| Частота | 2472 МГц |
| Ширина канала | 20 МГц |
| Стандарт | IEEE 802.11n |
| Защита | WPA2-PSK |
| IP точки доступа | `192.168.8.1/24` |
| DHCP-диапазон | `192.168.8.100–192.168.8.200` |
| Шлюз клиентов | `192.168.8.1` |
| DNS клиентов | `192.168.8.1` |
| Внешний интерфейс | `end0` |

## Ограничения и особенности

- На текущей конфигурации работает точка доступа в диапазоне 2,4 ГГц.
- Одновременный запуск точек доступа в диапазонах 2,4 и 5 ГГц пока не удалось реализовать.
- Возможность одновременной работы двух диапазонов зависит от поддержки соответствующего режима драйвером и прошивкой Wi-Fi.
- Канал 13 может не поддерживаться некоторыми клиентскими устройствами.
- Используется отдельный systemd-сервис `hostapd-wlan0.service`; стандартный `hostapd.service` замаскирован.

## 1. Подготовка Wi-Fi-интерфейса

Для интерфейса используется фиксированный MAC-адрес.

Файл `/etc/systemd/system/wlan0-mac.service`:

```ini
[Unit]
Description=Prepare wlan0 with ASUS MAC address
After=NetworkManager.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c '/usr/sbin/ip link set wlan0 down && /usr/sbin/iw dev wlan0 set type __ap && /usr/sbin/ip link set wlan0 address 00:0c:6e:42:44:5a && /usr/sbin/ip link set wlan0 up'

[Install]
WantedBy=multi-user.target
```

Сервис выполняет:
1. Отключение интерфейса.
2. Переключение в режим точки доступа.
3. Назначение MAC-адреса.
4. Включение интерфейса.

Включение при загрузке:

```bash
systemctl daemon-reload
systemctl enable wlan0-mac
```

## 2. Настройка hostapd

Файл `/etc/hostapd/hostapd-wlan0.conf`:

```ini
interface=wlan
