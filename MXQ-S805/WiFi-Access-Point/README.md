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
| IP устройства | DHCP | `192.168.50.1` |
| Шлюз | `192.168.1.1` | `192.168.50.1` |

Ethernet-интерфейс получает IP-адрес по DHCP. Его адрес может изменяться, поэтому в настройках NAT не используется фиксированный IP Ethernet.

Настройки Wi-Fi создаются отдельно и не требуют изменения конфигурации Ethernet.

### Схема

```text
                 Internet
                    |
              Main Router
               192.168.1.1
                    |
             Ethernet / eth0
                 DHCP
                    |
              +----------------+
              |   MXQ m201_N   |
              |   Amlogic S805 |
              |                |
              |  Armbian       |
              |  hostapd       |
              |  dnsmasq       |
              |  NAT           |
              +----------------+
                    |
                  wlan0
               192.168.50.1
                    |
             Wi-Fi Access Point
                    |
               +----+----+
               |         |
             Client    Client
           192.168.50.x
```

### Адресация Wi-Fi

| Параметр | Значение |
|---|---|
| IP интерфейса | `192.168.50.1/24` |
| DHCP range | `192.168.50.100–192.168.50.150` |
| DHCP lease | 12 часов |
| Default gateway | `192.168.50.1` |
| DNS server | `192.168.1.1` |

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

DNS-функция отключена, поскольку для Wi-Fi-клиентов используется DNS-сервер основного маршрутизатора.

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

## 8. IPv4 forwarding и NAT

Для доступа Wi-Fi-клиентов в интернет используется маршрутизация IPv4 и трансляция сетевых адресов (NAT).

Включён IPv4 forwarding:

```bash
sysctl net.ipv4.ip_forward
```

Ожидаемый результат:

```text
net.ipv4.ip_forward = 1
```

### NAT (MASQUERADE)

Для Wi-Fi-подсети используется правило:

```bash
iptables -t nat -A POSTROUTING \
    -s 192.168.50.0/24 \
    -o eth0 \
    -j MASQUERADE
```

Используется `MASQUERADE`, а не `SNAT` с фиксированным адресом.

Это важно, поскольку IP-адрес интерфейса `eth0` получается по DHCP и может изменяться. `MASQUERADE` автоматически использует текущий адрес выходного интерфейса.

### Firewall и Docker

В системе используется `iptables` с backend `nf_tables` (`iptables-nft`).

Docker самостоятельно создаёт и управляет своими цепочками firewall. Чтобы не изменять его правила, пользовательские правила маршрутизации размещены в цепочке `DOCKER-USER`.

Разрешается:

- пересылка новых и установленных соединений из `wlan0` в `eth0`;
- возвратный трафик из `eth0` в `wlan0` со статусом `ESTABLISHED,RELATED`;
- NAT для источников из подсети `192.168.50.0/24` при выходе через `eth0`.

Текущие правила:

```bash
# Wi-Fi -> Ethernet
iptables -I DOCKER-USER 1 \
    -i wlan0 -o eth0 \
    -s 192.168.50.0/24 \
    -m conntrack --ctstate NEW,ESTABLISHED,RELATED \
    -j ACCEPT

# Ethernet -> Wi-Fi (ответный трафик)
iptables -I DOCKER-USER 1 \
    -i eth0 -o wlan0 \
    -d 192.168.50.0/24 \
    -m conntrack --ctstate ESTABLISHED,RELATED \
    -j ACCEPT

# NAT
iptables -t nat -A POSTROUTING \
    -s 192.168.50.0/24 \
    -o eth0 \
    -j MASQUERADE
```

### Автоматическое восстановление firewall

Для восстановления пользовательских правил после перезагрузки используется отдельная systemd-служба.

Скрипт:

```text
/usr/local/sbin/mxq-ap-firewall
```

Systemd unit:

```text
/etc/systemd/system/mxq-ap-firewall.service
```

Служба запускается после `docker.service`, поскольку Docker создаёт цепочку `DOCKER-USER`.

Скрипт проверяет наличие правил перед добавлением. Повторный запуск не создаёт дубликаты.

Проверка:

```bash
systemctl status mxq-ap-firewall
```

Правила firewall не сохраняются полным снимком `iptables`, поэтому конфигурация Docker не перезаписывается.

## 9. Проверка работоспособности

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

### Проверка маршрутов и forwarding

```bash
ip route
sysctl net.ipv4.ip_forward
```

### Проверка firewall и NAT

```bash
iptables -vnL DOCKER-USER
iptables -t nat -vnL POSTROUTING
```

Счётчики пакетов позволяют проверить, что трафик Wi-Fi-клиентов проходит через правила forwarding и NAT.

### Проверка служб после перезагрузки

```bash
systemctl is-active hostapd
systemctl is-active dnsmasq
systemctl is-active docker
systemctl is-active mxq-ap-firewall
```

## 10. Результат

Проверено на реальном оборудовании:

 [x] RTL8189ES работает в режиме Access Point.
 [x] Устройства подключаются к Wi-Fi.
 [x] DHCP выдаёт адреса клиентам.
 [x] Wi-Fi-клиенты получают доступ к шлюзу.
 [x] Работает маршрутизация Wi-Fi → Ethernet.
 [x] Работает NAT через MASQUERADE.
 [x] DNS разрешается через основной маршрутизатор.
 [x] Ethernet использует DHCP, смена его адреса не требует изменения NAT.
  [x] Конфигурация и firewall проверены после перезагрузки.

## 11. Особенности и ограничения

1. Используется встроенный RTL8189ES с драйвером `rtl8189es`.
2. Возможности AP проверены на конкретной комбинации ядра и драйвера.
3. Для других сборок Armbian совместимость необходимо проверять отдельно.
4. Используется диапазон 2.4 GHz, канал 13.
5. Для постоянной эксплуатации необходимо установить собственный пароль Wi-Fi.

---

