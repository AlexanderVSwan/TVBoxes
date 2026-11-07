# MXQ S805 — Wi-Fi Access Point на Armbian

Настройка Android TV Box на базе **Amlogic S805** в качестве самостоятельной Wi-Fi точки доступа с использованием штатных Linux-компонентов.

Делаем точку доступа Wi-Fi. Ethernet используется как основное сетевое подключение, а встроенный Wi-Fi-модуль Realtek RTL8189ES работает в режиме Access Point.

## 1. Аппаратная платформа

| Компонент | Значение |
|---|---|
| Устройство | MXQ m201_N |
| SoC | Amlogic S805 |
| CPU | 4 × ARM Cortex-A5 |
| Wi-Fi | Realtek RTL8189ES |
| Wi-Fi interface | `wlan0` |
| Wi-Fi driver | `rtl8189es` |
| Ethernet | `eth0` |
| ОС | Armbian |
| Kernel | 6.12.28-current-meson |
| Userspace | Debian 13 (armhf) |
| Init system | systemd |

## 2. Сетевая архитектура

Используется разделение Ethernet- и Wi-Fi-сетей.

| Параметр | Ethernet | Wi-Fi AP |
|---|---|---|
| Интерфейс | `eth0` | `wlan0` |
| Подсеть | `192.168.1.0/24` | `192.168.50.0/24` |
| IP устройства | `192.168.1.128` (DHCP) | `192.168.50.1` |
| Шлюз | `192.168.1.1` | `192.168.50.1` |

Ethernet-интерфейс остаётся под управлением Netplan и systemd-networkd. Настройки Wi-Fi создаются отдельно и не требуют изменения конфигурации Ethernet.

### Схема

```text
                 Ethernet network
                 192.168.1.0/24
                       |
                  192.168.1.1
                       |
                    eth0
                       |
              +----------------+
              |   MXQ m201_N   |
              |   Amlogic S805 |
              |                |
              |  Armbian      |
              |  Debian 13    |
              |                |
              |  hostapd      |
              |  dnsmasq      |
              +----------------+
                       |
                     wlan0
                 192.168.50.1
                       |
                 Wi-Fi Access Point
                       |
                 +-----+-----+
                 |           |
               Client      Client
             192.168.50.x 192.168.50.x
```


## 3. Wi-Fi Access Point

Для создания точки доступа используется штатный `hostapd` с драйвером `nl80211`.

Возможность работы драйвера в режиме AP проверена через `iw list`. Режим AP поддерживается.


### Конфигурация hostapd

Файл:

```text
/etc/hostapd/hostapd.conf
```

```ini
interface=wlan0
driver=nl80211

ssid=Limited connection
country_code=RU
hw_mode=g
channel=13

ieee80211n=0
wmm_enabled=0

auth_algs=1
wpa=2
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
wpa_passphrase=CHANGE_THIS_PASSWORD

ignore_broadcast_ssid=0
```

Перед постоянной эксплуатацией необходимо установить собственный пароль WPA2.

Отключение 802.11n и WMM на первоначальном этапе позволяет использовать более простую конфигурацию для проверки совместимости драйвера. Возможность последующего включения этих функций требует отдельного тестирования.

## 4. Постоянный MAC-адрес Wi-Fi

Для изменения MAC-адреса используется штатный механизм `systemd.link`.

Исходный MAC RTL8189ES:

```text
d8:47:10:fe:b5:b5
```

Назначенный MAC:

```text
00:1a:92:7c:4d:31
```

Он использует OUI ASUS.

Файл:

```text
/etc/systemd/network/10-wlan0.link
```

```ini
[Match]
OriginalName=wlan0

[Link]
MACAddress=00:1A:92:7C:4D:31
MACAddressPolicy=none
```

Применение проверено через:

```bash
networkctl status wlan0
```

Ожидаемый результат:

```text
Link File: /etc/systemd/network/10-wlan0.link

Hardware Address: 00:1a:92:7c:4d:31
Permanent Hardware Address: d8:47:10:fe:b5:b5
```

Таким образом, исходный аппаратный MAC сохраняется, а сетевой интерфейс использует назначенный адрес.

**Примечание:** выбранный MAC является произвольно назначенным адресом с OUI ASUS, а не заводским MAC устройства ASUS. При использовании в других сетях следует учитывать возможность совпадения адресов.

## 5. Статический IP для Wi-Fi

Для настройки интерфейса применяется `systemd-networkd`.

Файл:

```text
/etc/systemd/network/20-wlan0-ap.network
```

```ini
[Match]
Name=wlan0

[Network]
Address=192.168.50.1/24
DHCP=no
LinkLocalAddressing=no
IPv6AcceptRA=no
```

Проверка:

```bash
networkctl status wlan0
ip -br addr show wlan0
```

Ожидаемый адрес:

```text
wlan0    UP    192.168.50.1/24
```

## 6. DHCP-сервер

Для автоматической выдачи IP-адресов используется `dnsmasq`.

DNS-функция отключена, поскольку системное разрешение имён уже выполняет `systemd-resolved`.

Файл:

```text
/etc/dnsmasq.d/mxq-ap.conf
```

```ini
# MXQ Wi-Fi Access Point
port=0

interface=wlan0
bind-interfaces

dhcp-authoritative
dhcp-range=192.168.50.100,192.168.50.150,255.255.255.0,12h

dhcp-option=option:router,192.168.50.1
dhcp-option=option:dns-server,192.168.1.1

log-dhcp
```

Параметры DHCP:

| Параметр | Значение |
|---|---|
| DHCP range | `192.168.50.100–192.168.50.150` |
| Netmask | `255.255.255.0` |
| Lease time | 12 hours |
| Default gateway | `192.168.50.1` |
| DNS server | `192.168.1.1` |
| DNS service in dnsmasq | Disabled |

`port=0` отключает DNS-сервер dnsmasq, но не его DHCP-функцию.

Это позволяет избежать конфликта с `systemd-resolved`, который использует локальные адреса `127.0.0.53` и `127.0.0.54` на порту 53.

Проверка конфигурации:

```bash
dnsmasq --test
```

Запуск:

```bash
systemctl restart dnsmasq
systemctl status dnsmasq
```

## 7. Автозапуск служб

Используются штатные systemd units, поставляемые пакетами Debian.

Проверка и включение:

```bash
systemctl unmask hostapd
systemctl enable hostapd
systemctl enable dnsmasq
```

Проверка состояния:

```bash
systemctl status hostapd
systemctl status dnsmasq
```

Конфигурация служб хранится в `/etc`, штатные unit-файлы в `/usr/lib/systemd/system` не изменяются.

## 8. Проверка работоспособности

### Проверка Wi-Fi-интерфейса

```bash
iw dev
iw list
ip -br addr
```

### Проверка hostapd

```bash
systemctl status hostapd
journalctl -u hostapd -n 50 --no-pager
```

### Проверка DHCP

```bash
systemctl status dnsmasq
journalctl -u dnsmasq -n 50 --no-pager
```

Список DHCP-аренд:

```bash
cat /var/lib/misc/dnsmasq.leases
```

Соседи Wi-Fi-интерфейса:

```bash
ip neigh show dev wlan0
```

### Проверка маршрутов

```bash
ip route
sysctl net.ipv4.ip_forward
```

## 11. Особенности и ограничения

1. Используется встроенный RTL8189ES с драйвером `rtl8189es`.
2. Возможности AP проверены на конкретной комбинации ядра и драйвера.
3. Для других сборок Armbian совместимость необходимо проверять отдельно.
6. Перед использованием в постоянной сети необходимо заменить тестовый пароль Wi-Fi.

---

