#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include <signal.h>
#include <dirent.h>

/* Пины GPIO для X98K (RK3528) */
#define GPIO_CLK 146
#define GPIO_DIO 129
#define GPIO_STB 142

/* Настройки яркости и ночного режима */
#define BRIGHTNESS_DAY   0x8F  /* Максимум (0x8B..0x8F) */
#define BRIGHTNESS_NIGHT 0x88  /* Минимум (1/16) */
#define NIGHT_START_HOUR 22    /* Начало ночи: 22:00 */
#define NIGHT_END_HOUR   8     /* Конец ночи: 08:00 */

/* Биты иконок (бит 3 = 0x08 в соответствующем четном байте буфера) */
#define ICON_USB   (1 << 0)  /* buf[0] - 0xC0 */
#define ICON_CARD  (1 << 1)  /* buf[1] - 0xC2 */
#define ICON_AM    (1 << 2)  /* buf[2] - 0xC4 */
#define ICON_PM    (1 << 3)  /* buf[3] - 0xC6 */
#define ICON_COLON (1 << 4)  /* buf[4] - 0xC8 */
#define ICON_WIFI  (1 << 5)  /* buf[5] - 0xCA */
#define ICON_LAN   (1 << 6)  /* buf[6] - 0xCC */

static int fd_clk = -1;
static int fd_dio = -1;
static int fd_stb = -1;
static volatile sig_atomic_t keep_running = 1;

/* Переменные для расчета загрузки CPU по /proc/stat */
static unsigned long long prev_total = 0;
static unsigned long long prev_idle  = 0;

/* Маски 4 позиций цифр (знакоместа 0..3) */
static const uint8_t POS_MASKS[4] = { 0x80, 0x40, 0x20, 0x10 };

/* Преобразование ASCII-символа в 7-сегментную маску (биты 0..6 = сегменты a..g) */
static uint8_t char_to_mask(char c) {
    switch (c) {
        case '0': case 'O': return 0x3F;
        case '1':           return 0x06;
        case '2':           return 0x5B;
        case '3':           return 0x4F;
        case '4':           return 0x66;
        case '5': case 'S': return 0x6D;
        case '6':           return 0x7D;
        case '7':           return 0x07;
        case '8':           return 0x7F;
        case '9':           return 0x6F;
        case 'A': case 'a': return 0x77;
        case 'b':           return 0x7C;
        case 'C':           return 0x39;
        case 'd':           return 0x5E;
        case 'E':           return 0x79;
        case 'F': case 'f': return 0x71;
        case 'H':           return 0x76;
        case 'L': case 'l': return 0x38;
        case 'o':           return 0x5C;
        case 'P':           return 0x73;
        case 'U':           return 0x3E;
        case '-':           return 0x40;
        case '_':           return 0x08;
        default:            return 0x00;
    }
}

static void handle_sig(int sig) {
    (void)sig;
    keep_running = 0;
}

/* Экспорт и открытие GPIO с удержанием файлового дескриптора */
static int setup_gpio(int pin) {
    char path[64];
    char buf[16];
    int fd;

    snprintf(path, sizeof(path), "/sys/class/gpio/gpio%d/value", pin);
    if (access(path, F_OK) != 0) {
        fd = open("/sys/class/gpio/export", O_WRONLY);
        if (fd >= 0) {
            int len = snprintf(buf, sizeof(buf), "%d", pin);
            if (write(fd, buf, len) < 0) {}
            close(fd);
        }
        for (int i = 0; i < 50; i++) {
            if (access(path, F_OK) == 0) break;
            usleep(10000);
        }
    }

    snprintf(path, sizeof(path), "/sys/class/gpio/gpio%d/direction", pin);
    fd = open(path, O_WRONLY);
    if (fd >= 0) {
        if (write(fd, "out", 3) < 0) {}
        close(fd);
    }

    snprintf(path, sizeof(path), "/sys/class/gpio/gpio%d/value", pin);
    return open(path, O_WRONLY);
}

static inline void set_pin(int fd, int val) {
    if (write(fd, val ? "1" : "0", 1) < 0) {}
}

static void send_byte(uint8_t b) {
    for (int i = 0; i < 8; i++) {
        set_pin(fd_clk, 0);
        set_pin(fd_dio, (b >> i) & 1);
        set_pin(fd_clk, 1);
    }
}

static void send_cmd(uint8_t cmd) {
    set_pin(fd_stb, 0);
    send_byte(cmd);
    set_pin(fd_stb, 1);
}

/* Отрисовка 4 символов, масок иконок и яркости */
static void update_display(const char *text, uint8_t icons, uint8_t brightness) {
    uint8_t buf[7] = {0};

    for (int pos = 0; pos < 4 && text[pos] != '\0'; pos++) {
        uint8_t seg_mask = char_to_mask(text[pos]);
        uint8_t pos_bit  = POS_MASKS[pos];

        for (int seg = 0; seg < 7; seg++) {
            if ((seg_mask >> seg) & 1) {
                buf[seg] |= pos_bit;
            }
        }
    }

    for (int seg = 0; seg < 7; seg++) {
        if ((icons >> seg) & 1) {
            buf[seg] |= 0x08;
        }
    }

    send_cmd(0x40);
    set_pin(fd_stb, 0);
    send_byte(0xC0);
    for (int seg = 0; seg < 7; seg++) {
        send_byte(buf[seg]);
        send_byte(0x00);
    }
    set_pin(fd_stb, 1);
    send_cmd(brightness);
}

/* Вспомогательное чтение первой строки из sysfs/proc-файла */
static int read_first_line(const char *path, char *out, size_t max_len) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) return -1;
    ssize_t n = read(fd, out, max_len - 1);
    close(fd);
    if (n <= 0) return -1;
    out[n] = '\0';
    char *nl = strchr(out, '\n');
    if (nl) *nl = '\0';
    return 0;
}

/* Чтение температуры CPU (в градусах Цельсия, 0..99) */
static int get_cpu_temp(void) {
    char buf[32];
    if (read_first_line("/sys/class/thermal/thermal_zone0/temp", buf, sizeof(buf)) == 0) {
        int temp_mc = atoi(buf);
        int temp_c = (temp_mc > 1000) ? (temp_mc / 1000) : temp_mc;
        if (temp_c < 0) temp_c = 0;
        if (temp_c > 99) temp_c = 99;
        return temp_c;
    }
    return 0;
}

/* Расчет загрузки CPU в процентах (0..99) по дельте /proc/stat */
static int get_cpu_usage(void) {
    char buf[256];
    if (read_first_line("/proc/stat", buf, sizeof(buf)) != 0) {
        return 0;
    }

    unsigned long long user = 0, nice = 0, system = 0, idle = 0;
    unsigned long long iowait = 0, irq = 0, softirq = 0, steal = 0;

    if (sscanf(buf, "cpu %llu %llu %llu %llu %llu %llu %llu %llu",
               &user, &nice, &system, &idle, &iowait, &irq, &softirq, &steal) < 4) {
        return 0;
    }

    unsigned long long idle_all = idle + iowait;
    unsigned long long total = user + nice + system + idle_all + irq + softirq + steal;

    unsigned long long diff_total = total - prev_total;
    unsigned long long diff_idle  = idle_all - prev_idle;

    prev_total = total;
    prev_idle  = idle_all;

    if (diff_total == 0) return 0;

    int usage = (int)((100ULL * (diff_total - diff_idle)) / diff_total);
    if (usage < 0) usage = 0;
    if (usage > 99) usage = 99; /* Чтобы всегда помещалось в 2 разряда */
    return usage;
}

/* Автоматический опрос статуса оборудования (LAN, Wi-Fi, USB, SD-Card) */
static uint8_t detect_hardware_icons(void) {
    uint8_t icons = 0;
    DIR *d;
    struct dirent *de;
    char path[256], state[32];

    /* 1. Проверка сети (/sys/class/net) */
    d = opendir("/sys/class/net");
    if (d) {
        while ((de = readdir(d)) != NULL) {
            if (de->d_name[0] == '.') continue;
            snprintf(path, sizeof(path), "/sys/class/net/%s/operstate", de->d_name);
            if (read_first_line(path, state, sizeof(state)) == 0 && strcmp(state, "up") == 0) {
                if (strncmp(de->d_name, "eth", 3) == 0 ||
                    strncmp(de->d_name, "end", 3) == 0 ||
                    strncmp(de->d_name, "enp", 3) == 0) {
                    icons |= ICON_LAN;
                } else if (strncmp(de->d_name, "wlan", 4) == 0 ||
                           strncmp(de->d_name, "wlp", 3) == 0 ||
                           strncmp(de->d_name, "wlx", 3) == 0) {
                    icons |= ICON_WIFI;
                }
            }
        }
        closedir(d);
    }

    /* 2. Проверка накопителей (/sys/block) */
    d = opendir("/sys/block");
    if (d) {
        while ((de = readdir(d)) != NULL) {
            if (strncmp(de->d_name, "sd", 2) == 0) {
                icons |= ICON_USB;
            } else if (strncmp(de->d_name, "mmcblk", 6) == 0) {
                snprintf(path, sizeof(path), "/sys/block/%s/device/type", de->d_name);
                if (read_first_line(path, state, sizeof(state)) == 0 && strcmp(state, "SD") == 0) {
                    icons |= ICON_CARD;
                }
            }
        }
        closedir(d);
    }

    return icons;
}

int main(void) {
    signal(SIGINT,  handle_sig);
    signal(SIGTERM, handle_sig);

    fd_clk = setup_gpio(GPIO_CLK);
    fd_dio = setup_gpio(GPIO_DIO);
    fd_stb = setup_gpio(GPIO_STB);

    if (fd_clk < 0 || fd_dio < 0 || fd_stb < 0) {
        fprintf(stderr, "tm1628d: Ошибка открытия GPIO\n");
        return 1;
    }

    /* Первичная инициализация счетчика CPU */
    get_cpu_usage();

    /* 1. Сразу при старте показываем "LoAd" */
    update_display("LoAd", 0, BRIGHTNESS_DAY);
    sleep(2);

    uint8_t hw_icons = 0;
    int step = 0; /* 0, 1 = Часы (2 сек); 2 = Температура:Загрузка (1 сек) */

    /* 2. Основной цикл */
    while (keep_running) {
        time_t now = time(NULL);
        struct tm *t = localtime(&now);

        /* Обновляем статус иконок железа в начале каждого 3-секундного цикла */
        if (step == 0) {
            hw_icons = detect_hardware_icons();
        }

        /* Выбираем дневную или ночную яркость */
        uint8_t br = BRIGHTNESS_DAY;
        if (t->tm_hour >= NIGHT_START_HOUR || t->tm_hour < NIGHT_END_HOUR) {
            br = BRIGHTNESS_NIGHT;
        }

        char disp_str[8];
        uint8_t icons = hw_icons;

        if (step < 2) {
            /* Первые 2 секунды: выводим время ЧЧ:ММ */
            snprintf(disp_str, sizeof(disp_str), "%02d%02d", t->tm_hour, t->tm_min);
            /* На step == 0 двоеточие горит, на step == 1 гаснет */
            if (step == 0) {
                icons |= ICON_COLON;
            }
        } else {
            /* Третья секунда: выводим Температуру и Загрузку CPU через двоеточие (TT:LL) */
            int temp = get_cpu_temp();
            int load = get_cpu_usage();
            snprintf(disp_str, sizeof(disp_str), "%02d%02d", temp, load);
            icons |= ICON_COLON;
        }

        update_display(disp_str, icons, br);

        step = (step + 1) % 3;
        sleep(1);
    }

    /* 3. При завершении работы оставляем гореть надпись " oFF" на мягкой яркости */
    update_display(" oFF", 0, BRIGHTNESS_NIGHT);

    close(fd_clk);
    close(fd_dio);
    close(fd_stb);
    return 0;
}
