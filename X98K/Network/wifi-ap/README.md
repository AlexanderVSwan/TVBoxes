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
interface=wlan0
driver=nl80211

ssid=NFQUEUE_300

country_code=RU
hw_mode=g
channel=13

ieee80211n=1

wpa=2
wpa_key_mgmt=WPA-PSK
wpa_passphrase=CHANGE_THIS_PASSWORD
```

Параметры:
- Диапазон 2,4 ГГц.
- Канал 13.
- Ширина канала 20 МГц.
- IEEE 802.11n.
- Защита WPA2-PSK.

Вместо `CHANGE_THIS_PASSWORD` необходимо указать собственный пароль Wi-Fi.

## 3. Systemd-сервис точки доступа

Файл `/etc/systemd/system/hostapd-wlan0.service`:

```ini
[Unit]
Description=Wi-Fi Access Point wlan0
Requires=wlan0-mac.service
After=NetworkManager.service wlan0-mac.service

[Service]
Type=simple
ExecStartPre=/usr/sbin/ip addr replace 192.168.8.1/24 dev wlan0
ExecStart=/usr/sbin/hostapd /etc/hostapd/hostapd-wlan0.conf
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
```

Сервис:
- Ожидает подготовки Wi-Fi-интерфейса.
- Назначает интерфейсу адрес `192.168.8.1/24`.
- Запускает `hostapd`.
- Перезапускает его при аварийном завершении.

Включение:

```bash
systemctl daemon-reload
systemctl enable hostapd-wlan0
systemctl start hostapd-wlan0
```

## 4. DHCP и локальный DNS

Для выдачи адресов клиентам используется `dnsmasq`.

Файл `/etc/dnsmasq.d/wlan0.conf`:

```ini
# Wi-Fi access point only
interface=wlan0
listen-address=192.168.8.1
bind-interfaces
except-interface=end0

# DHCP
dhcp-authoritative
dhcp-range=192.168.8.100,192.168.8.200,255.255.255.0,12h
dhcp-option=option:router,192.168.8.1
dhcp-option=option:dns-server,192.168.8.1

# DNS via local DoH proxy
no-resolv
server=127.0.0.1#5053

domain-needed
bogus-priv
```

Настройки DHCP:
- Адреса клиентов: `192.168.8.100–192.168.8.200`.
- Шлюз: `192.168.8.1`.
- DNS: `192.168.8.1`.

DNS-запросы передаются локальному прокси на `127.0.0.1:5053`.

Подробная настройка DNS и DoH описывается отдельно в разделе [`network/dns`](../dns/README.md).

Включение:

```bash
systemctl enable dnsmasq
systemctl restart dnsmasq
```

## 5. Включение IPv4 forwarding

Файл `/etc/sysctl.d/99-ip-forward.conf`:

```ini
net.ipv4.ip_forward=1
```

Применение:

```bash
sysctl --system
```

Проверка:

```bash
sysctl net.ipv4.ip_forward
```

Ожидаемое значение:

```text
net.ipv4.ip_forward = 1
```

## 6. Настройка NAT через nftables

Файл `/etc/nftables.d/x98k-nat.nft`:

```nft
table ip x98k_nat {
    chain forward {
        type filter hook forward priority filter; policy accept;

        iifname "wlan0" oifname "end0" ip saddr 192.168.8.0/24 counter accept
        iifname "end0" oifname "wlan0" ip daddr 192.168.8.0/24 ct state established,related counter accept
    }

    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;

        ip saddr 192.168.8.0/24 oifname "end0" counter masquerade
    }
}
```

Правила обеспечивают:
- Пересылку трафика клиентов Wi-Fi в Ethernet.
- Пропуск ответного трафика существующих соединений.
- NAT masquerade для сети `192.168.8.0/24`.

## 7. Systemd-сервис NAT

Файл `/etc/systemd/system/x98k-nat.service`:

```ini
[Unit]
Description=X98K Wi-Fi NAT and forwarding rules
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=-/usr/sbin/nft delete table ip x98k_nat
ExecStart=/usr/sbin/nft -f /etc/nftables.d/x98k-nat.nft
ExecStop=-/usr/sbin/nft delete table ip x98k_nat

[Install]
WantedBy=multi-user.target
```

Включение:

```bash
systemctl daemon-reload
systemctl enable x98k-nat
systemctl start x98k-nat
```

## 8. Проверка работы

Состояние служб:

```bash
systemctl status wlan0-mac
systemctl status hostapd-wlan0
systemctl status dnsmasq
systemctl status x98k-nat
```

Информация о Wi-Fi:

```bash
iw dev wlan0 info
```

Подключённые клиенты:

```bash
iw dev wlan0 station dump
```

DHCP-аренды:

```bash
cat /var/lib/misc/dnsmasq.leases
```

Правила NAT:

```bash
nft list table ip x98k_nat
```

IPv4 forwarding:

```bash
sysctl net.ipv4.ip_forward
```

## 9. Изменение канала Wi-Fi

Канал задаётся параметром `channel` в `/etc/hostapd/hostapd-wlan0.conf`.

Например:

```ini
channel=13
```

После изменения:

```bash
systemctl restart hostapd-wlan0
```

Проверка:

```bash
iw dev wlan0 info
```

## Примечания

- Реальный пароль Wi-Fi не следует публиковать в репозитории.
- При выборе канала учитывайте региональные ограничения и поддержку клиентских устройств.
- Настройки DHCP и NAT рассчитаны на использование `end0` в качестве внешнего интерфейса.
- Перед применением конфигурации на другом устройстве необходимо проверить имена интерфейсов.
- После перезагрузки следует проверить автоматический запуск всех служб.
