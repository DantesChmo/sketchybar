// Единый event-provider для sketchybar.
//
// Один долгоживущий процесс держит mach-порт к бару и напрямую обновляет
// items (clock/cpu/ram/battery/calendar) без единого fork/exec.
// Метрики берём из ядра (host_processor_info / host_statistics64 / IOKit),
// поэтому `top`, `vm_stat`, `pmset`, `date` больше не запускаются.

#include "mach.h"
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <unistd.h>
#include <time.h>
#include <locale.h>
#include <sys/sysctl.h>
#include <mach/mach.h>
#include <mach/mach_host.h>
#include <mach/processor_info.h>
#include <mach/machine.h>
#include <mach/vm_statistics.h>
#include <ctype.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/ps/IOPowerSources.h>
#include <IOKit/ps/IOPSKeys.h>
#include <Carbon/Carbon.h>

// mach.c ссылается на g_name внутри mach_server_begin (мы его не вызываем,
// но символ должен разрешиться при линковке).
char g_name[256] = "sketchybar_metrics";

#define COLOR_WHITE "0xffffffff"
#define COLOR_RED   "0xffed8796"
#define COLOR_GREEN "0xff9dd274"

// ---- отправка команды бару через mach (без fork) ----
// Возвращает true, если бар найден и сообщение отправлено.
static bool bar(int argc, char** argv) {
  mach_port_t port = mach_get_bs_port("git.felix.sketchybar");
  if (!port) return false;

  uint32_t len = 1;               // финальный '\0'
  int argl[argc];
  for (int i = 0; i < argc; i++) { argl[i] = strlen(argv[i]); len += argl[i] + 1; }

  char* msg = malloc(len);
  char* t = msg;
  for (int i = 0; i < argc; i++) { memcpy(t, argv[i], argl[i]); t += argl[i]; *t++ = '\0'; }
  *t = '\0';

  char* rsp = mach_send_message(port, msg, len, true);
  free(msg);
  if (rsp) free(rsp);
  return true;
}

// ---- CPU: дельта тиков между вызовами (как это делает top внутри) ----
static uint64_t g_prev_total = 0, g_prev_idle = 0;
static double cpu_usage(void) {
  natural_t ncpu = 0;
  processor_info_array_t info = NULL;
  mach_msg_type_number_t cnt = 0;
  if (host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                          &ncpu, &info, &cnt) != KERN_SUCCESS) return -1;

  uint64_t total = 0, idle = 0;
  processor_cpu_load_info_t load = (processor_cpu_load_info_t)info;
  for (natural_t i = 0; i < ncpu; i++) {
    for (int s = 0; s < CPU_STATE_MAX; s++) total += load[i].cpu_ticks[s];
    idle += load[i].cpu_ticks[CPU_STATE_IDLE];
  }
  vm_deallocate(mach_task_self(), (vm_address_t)info, cnt * sizeof(integer_t));

  double usage = -1;
  uint64_t dt = total - g_prev_total, di = idle - g_prev_idle;
  if (g_prev_total && dt > 0) usage = 100.0 * (double)(dt - di) / (double)dt;
  g_prev_total = total; g_prev_idle = idle;
  return usage;
}

// ---- RAM: (active + wired + compressed) / total, как в Activity Monitor ----
static double ram_usage(void) {
  vm_size_t page_size = 0;
  host_page_size(mach_host_self(), &page_size);

  vm_statistics64_data_t vm;
  mach_msg_type_number_t cnt = HOST_VM_INFO64_COUNT;
  if (host_statistics64(mach_host_self(), HOST_VM_INFO64,
                        (host_info64_t)&vm, &cnt) != KERN_SUCCESS) return -1;

  uint64_t used = ((uint64_t)vm.active_count + vm.wire_count
                   + vm.compressor_page_count) * (uint64_t)page_size;

  int64_t total = 0; size_t sz = sizeof(total);
  if (sysctlbyname("hw.memsize", &total, &sz, NULL, 0) != 0 || total <= 0) return -1;
  return 100.0 * (double)used / (double)total;
}

// ---- Battery: IOKit ----
static int battery(bool* charging) {
  int percent = -1; *charging = false;
  CFTypeRef blob = IOPSCopyPowerSourcesInfo();
  if (!blob) return -1;
  CFArrayRef list = IOPSCopyPowerSourcesList(blob);
  if (list) {
    for (CFIndex i = 0; i < CFArrayGetCount(list); i++) {
      CFDictionaryRef ps = IOPSGetPowerSourceDescription(blob, CFArrayGetValueAtIndex(list, i));
      if (!ps) continue;
      CFNumberRef cap = CFDictionaryGetValue(ps, CFSTR(kIOPSCurrentCapacityKey));
      if (cap) CFNumberGetValue(cap, kCFNumberIntType, &percent);
      CFStringRef state = CFDictionaryGetValue(ps, CFSTR(kIOPSPowerSourceStateKey));
      if (state && CFStringCompare(state, CFSTR(kIOPSACPowerValue), 0) == kCFCompareEqualTo)
        *charging = true;
    }
    CFRelease(list);
  }
  CFRelease(blob);
  return percent;
}

// Nerd Font глифы батареи (Private Use Area) — байтами UTF-8, чтобы не зависеть
// от вставки PUA-символов в исходник.
static const char* batt_icon(int p, bool charging) {
  if (charging) return "\xf3\xb0\x82\x84"; // 󰂄
  if (p >= 90)  return "\xf3\xb0\x81\xb9"; // 󰁹
  if (p >= 80)  return "\xf3\xb0\x82\x82"; // 󰂂
  if (p >= 70)  return "\xf3\xb0\x82\x81"; // 󰂁
  if (p >= 60)  return "\xf3\xb0\x82\x80"; // 󰂀
  if (p >= 50)  return "\xf3\xb0\x81\xbf"; // 󰁿
  if (p >= 40)  return "\xf3\xb0\x81\xbe"; // 󰁾
  if (p >= 30)  return "\xf3\xb0\x81\xbd"; // 󰁽
  if (p >= 20)  return "\xf3\xb0\x81\xbc"; // 󰁼
  if (p >= 10)  return "\xf3\xb0\x81\xbb"; // 󰁻
  return "\xf3\xb0\x81\xba";               // 󰁺
}

static int clamp(double v) { int p = (int)(v + 0.5); return p < 0 ? 0 : (p > 100 ? 100 : p); }

// ---- Раскладка клавиатуры (one-shot режим `--lang`) ----
// Запускается коротко живущим процессом по событию смены раскладки от самого
// sketchybar. Спрашивает у системы АКТУАЛЬНЫЙ язык и ставит label. Короткий
// процесс всегда читает свежее значение (в отличие от зависшего долгоживущего).
static int emit_keyboard(void) {
  TISInputSourceRef src = TISCopyCurrentKeyboardInputSource();
  if (!src) return 1;

  char code[8] = "??";
  CFArrayRef langs = (CFArrayRef)TISGetInputSourceProperty(src, kTISPropertyInputSourceLanguages);
  if (langs && CFArrayGetCount(langs) > 0) {
    CFStringRef l = (CFStringRef)CFArrayGetValueAtIndex(langs, 0);  // напр. "en", "ru"
    char buf[16] = {0};
    if (CFStringGetCString(l, buf, sizeof buf, kCFStringEncodingUTF8) && buf[0]) {
      code[0] = toupper((unsigned char)buf[0]);
      code[1] = buf[1] ? toupper((unsigned char)buf[1]) : '\0';
      code[2] = '\0';
    }
  }
  CFRelease(src);

  char label[32];
  snprintf(label, sizeof label, "label=%s", code);
  char* c[] = {"--set", "language", label};
  return bar(3, c) ? 0 : 1;
}

int main(int argc, char** argv) {
  // one-shot: прочитать раскладку и выйти (вызывается по событию из sketchybar)
  if (argc > 1 && strcmp(argv[1], "--lang") == 0) return emit_keyboard();

  setlocale(LC_TIME, "");   // для календаря: локализованные месяц/день
  cpu_usage();              // праймим счётчики тиков

  int tick = 0, dead = 0;
  char a[6][64];

  for (;; tick++, sleep(1)) {
    // --- часы: каждую секунду ---
    time_t now = time(NULL);
    struct tm tmv; localtime_r(&now, &tmv);
    char hms[32]; strftime(hms, sizeof hms, "%H:%M:%S", &tmv);
    snprintf(a[0], 64, "label=%s", hms);
    { char* c[] = {"--set", "clock", a[0]};
      if (!bar(3, c)) { if (++dead > 5) return 0; continue; } else dead = 0; }

    // раскладка клавиатуры — вне провайдера: sketchybar сам ловит системное
    // событие и дёргает `sketchybar_metrics --lang` (см. sketchybarrc).

    // --- CPU: каждые 2с ---
    if (tick % 2 == 0) {
      double u = cpu_usage();
      if (u >= 0) {
        int p = clamp(u);
        snprintf(a[1], 64, "label=%3d%%", p);
        snprintf(a[2], 64, "icon.color=%s", p >= 85 ? COLOR_RED : COLOR_WHITE);
        char* c[] = {"--set", "cpu", a[1], a[2]};
        bar(4, c);
      }
    }

    // --- RAM: каждые 5с ---
    if (tick % 5 == 0) {
      double r = ram_usage();
      if (r >= 0) {
        int p = clamp(r);
        snprintf(a[1], 64, "label=%3d%%", p);
        snprintf(a[2], 64, "icon.color=%s", p >= 85 ? COLOR_RED : COLOR_WHITE);
        char* c[] = {"--set", "ram", a[1], a[2]};
        bar(4, c);
      }
    }

    // --- Battery: каждые 10с ---
    if (tick % 10 == 0) {
      bool chg; int p = battery(&chg);
      if (p >= 0) {
        snprintf(a[1], 64, "icon=%s", batt_icon(p, chg));
        snprintf(a[2], 64, "icon.color=%s", chg ? COLOR_GREEN : (p < 10 ? COLOR_RED : COLOR_WHITE));
        snprintf(a[3], 64, "label=%3d%%", p);
        char* c[] = {"--set", "battery", a[1], a[2], a[3]};
        bar(5, c);
      }
    }

    // --- Calendar: каждые 60с ---
    if (tick % 60 == 0) {
      char d[64]; strftime(d, sizeof d, "%d %b, %a", &tmv);
      snprintf(a[1], 64, "label=%s", d);
      char* c[] = {"--set", "calendar", a[1]};
      bar(3, c);
    }
  }
}
