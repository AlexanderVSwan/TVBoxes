## X98K (RK3528): запуск Bluetooth в Armbian

### Устройство и окружение

- **Приставка:** X98K
- **SoC:** Rockchip RK3528
- **ОС:** Armbian на базе образа X88 Pro
- **Ядро:** `6.1.115-vendor-rk35xx`
- **DTB:** `/boot/dtb/rockchip/rk3528-x98k-u3.dtb`
- **Wi-Fi/Bluetooth:** combo-модуль семейства AIC8800D80
- **Bluetooth UART:** `/dev/ttyS2`
- **Скорость UART:** 1 500 000 бод
- **Bluetooth stack:** BlueZ 5.85

Точная маркировка установленного беспроводного модуля пока не подтверждена.

### Проблема

Изначально Bluetooth не запускался штатной службой `aic-bluetooth`. В исходном скрипте `/usr/bin/aic-bluetooth` использовался UART `/dev/ttyS1`, которого не удалось использовать для инициализации контроллера на данной конфигурации.

Попытка использовать `btattach` с параметрами H4 также завершалась ошибкой тайм-аута HCI Reset (`Opcode 0x0c03 failed: -110`).

При этом в Device Tree Bluetooth описан как отдельное устройство, подключённое по UART, а сообщения ядра подтверждали работу платформенного драйвера Bluetooth.

### Решение

Рабочая команда ручной инициализации:

```bash
rfkill block all
sleep 1
rfkill unblock all
sleep 2
hciattach -s 1500000 /dev/ttyS2 any 1500000 flow nosleep
```

После выполнения команды вывод содержал:

```text
Device setup complete
```

Контроллер определялся системой:

```text
hci0: Type: Primary  Bus: UART
BD Address: 0B:3B:22:AC:88:20
UP RUNNING
HCI Version: 5.4
LMP Version: 5.4
Manufacturer: not assigned (2875)
```

### Настройка автоматического запуска

Создан резервный экземпляр исходного скрипта и файла службы. Для запуска Bluetooth через systemd изменён `/usr/bin/aic-bluetooth`:

```bash
#!/bin/bash
exec /usr/bin/hciattach -n -s 1500000 /dev/ttyS2 any 1500000 flow nosleep
```

Параметр `-n` предотвращает переход `hciattach` в фоновый режим. Благодаря этому systemd может отслеживать процесс и не завершает службу сразу после инициализации контроллера.

Создано переопределение службы `/etc/systemd/system/aic-bluetooth.service`:

```ini
[Unit]
Description=AIC8800 Bluetooth HCI UART
After=bluetooth.service
Requires=bluetooth.service

[Service]
Type=simple
ExecStart=/usr/bin/aic-bluetooth
Restart=no

[Install]
WantedBy=multi-user.target
```

Применение конфигурации и включение службы:

```bash
systemctl daemon-reload
systemctl enable aic-bluetooth
```

После изменения скрипта служба запускалась с параметром `-n`, а контроллер оставался активным.

### Проверка работоспособности

Команда:

```bash
hciconfig -a
```

показывала контроллер `hci0` в состоянии `UP RUNNING`. При повторных проверках увеличивались счётчики RX и HCI events, ошибок не наблюдалось.

В `bluetoothctl` успешно выполнялось сканирование:

```text
power on
scan on
```

Обнаруживались устройства поблизости, включая Galaxy Watch3 и Android TV. Остановка сканирования командой `scan off` проходила штатно.

Это подтверждает работу UART-соединения, инициализацию HCI и обнаружение Bluetooth-устройств через BlueZ.


### Проверка автозапуска после перезагрузки

После настройки службы выполнена перезагрузка системы. Bluetooth автоматически запустился без ручного вмешательства.

Результат `systemctl status aic-bluetooth`:

```text
Loaded: loaded (/etc/systemd/system/aic-bluetooth.service; enabled)
Active: active (running)
Main PID: 798 (hciattach)
```

Процесс запущен с параметрами:

```text
/usr/bin/hciattach -n -s 1500000 /dev/ttyS2 any 1500000 flow nosleep
```

После перезагрузки `hciconfig -a` показывает:

```text
hci0: Type: Primary Bus: UART
BD Address: 0B:3B:22:AC:88:20
UP RUNNING
HCI Version: 5.4
LMP Version: 5.4
```

Команда `bluetoothctl list` также успешно обнаруживает контроллер:

```text
Controller 0B:3B:22:AC:88:20 x88pro [default]
```

Ранее выполненное сканирование через `bluetoothctl` обнаруживало находящиеся поблизости Bluetooth-устройства.

**Итог:** Bluetooth на X98K (RK3528) под Armbian работает через UART `/dev/ttyS2`; автоматический запуск после перезагрузки подтверждён. Используется штатный `hciattach` и BlueZ, без разработки собственного драйвера ядра.



### Итог

Bluetooth на X98K под Armbian удалось запустить без разработки собственного драйвера ядра, используя `hciattach`, UART `/dev/ttyS2` и штатный стек BlueZ.

