#import "LQSStrings.h"

// Tables: Resources/strings/<lang>.json, keyed by Android resource name
// (scripts/export_res_strings.py over SettingsLib + SystemUI res). LQSL accepts
// either a resource name or an English text listed in Aliases().

static NSString *gDir;
static NSDictionary *gTable, *gEnglish;
static NSString *gLang;

void LQSStringsSetDirectory(NSString *dir) { gDir = [dir copy]; gTable = nil; gEnglish = nil; }

// iOS language id -> Android resource qualifier used for the file names.
static NSArray<NSString *> *Candidates(NSString *ios) {
    NSMutableArray *c = [NSMutableArray array];
    NSDictionary *special = @{@"zh-Hans": @"zh-CN", @"zh-Hant": @"zh-TW", @"zh-HK": @"zh-HK", @"id": @"in", @"he": @"iw", @"yi": @"ji", @"nb": @"nb", @"fil": @"tl"};
    NSArray *parts = [ios componentsSeparatedByString:@"-"];
    NSString *lang = parts.firstObject;
    for (NSString *k in special) if ([ios hasPrefix:k]) [c addObject:special[k]];
    if (parts.count >= 2) [c addObject:[NSString stringWithFormat:@"%@-%@", lang, parts.lastObject]];
    [c addObject:special[lang] ?: lang];
    return c;
}

// English text used in code -> SystemUI / SettingsLib resource name.
static NSDictionary *Aliases(void) {
    static NSDictionary *a;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        a = @{@"On": @"switch_bar_on", @"Off": @"switch_bar_off", @"Unavailable": @"tile_unavailable",
              @"Wi‑Fi": @"quick_settings_wifi_label", @"Wi-Fi": @"quick_settings_wifi_label", @"Internet": @"quick_settings_internet_label",
              @"Bluetooth": @"quick_settings_bluetooth_label", @"Connected": @"quick_settings_connected",
              @"Networks available": @"quick_settings_networks_available", @"Clear all": @"clear_all_notifications_text",
              @"Manage": @"manage_notifications_text", @"Notifications": @"notification_section_header_alerting",
              @"No SIM": @"keyguard_missing_sim_message_short", @"Saved": @"wifi_remembered",
              @"Wi-Fi is off": @"wifi_is_off", @"Pair new device": @"quick_settings_pair_hearing_devices",
              @"Bluetooth settings": @"accessibility_bluetooth_device_settings_gear",
              @"See all": @"accessibility_bluetooth_device_settings_see_all",
              @"Play": @"controls_media_button_play",
              @"Pause": @"controls_media_button_pause", @"Next track": @"controls_media_button_next",
              @"Previous track": @"controls_media_button_prev", @"No notifications": @"empty_shade_text",
              @"Edit": @"accessibility_quick_settings_edit", @"Settings": @"accessibility_quick_settings_settings",
              @"Power menu": @"accessibility_quick_settings_power_menu",
              @"Auto brightness": @"quick_settings_brightness_dialog_auto_brightness_label"};
    });
    return a;
}

static NSDictionary *Own(NSString *lang) {
    if (![lang hasPrefix:@"ru"]) return @{};
    return @{@"Show less": @"Свернуть", @"Connecting to %@…": @"Подключение к %@…", @"now": @"сейчас",
             @"Searching for networks…": @"Поиск сетей…", @"Tap a network to connect": @"Нажмите на сеть, чтобы подключиться",
             @"Tap to connect or disconnect a device": @"Нажмите, чтобы подключить или отключить устройство",
             @"This phone": @"Этот телефон", @"Reset": @"Сбросить", @"OK": @"ОК", @"Cancel": @"Отмена", @"Undo": @"Отменить", @"You're all caught up": @"Уведомлений нет", @"Ring": @"Звонок", @"Mute": @"Без звука"};
}

static NSDictionary *Read(NSString *lang) {
    NSData *d = gDir ? [NSData dataWithContentsOfFile:[gDir stringByAppendingPathComponent:[lang stringByAppendingPathExtension:@"json"]]] : nil;
    NSDictionary *j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
    return [j isKindOfClass:NSDictionary.class] ? j : nil;
}

static void Load(void) {
    if (gTable) return;
    NSString *pref = NSLocale.preferredLanguages.firstObject ?: @"en";
    gEnglish = Read(@"en") ?: @{};
    NSMutableDictionary *t = [NSMutableDictionary dictionary];
    gLang = @"en";
    for (NSString *cand in Candidates(pref)) {
        NSDictionary *j = Read(cand);
        if (j.count) { [t addEntriesFromDictionary:j]; gLang = cand; break; }
    }
    [t addEntriesFromDictionary:Own(pref)];
    gTable = t;
}

NSString *LQSL(NSString *key) {
    Load();
    NSString *v = gTable[key] ?: gEnglish[key];
    if (v.length) return v;
    NSString *res = Aliases()[key];
    if (res) v = gTable[res] ?: gEnglish[res];
    return v.length ? v : key;
}

NSString *LQSStringsLanguage(void) { Load(); return gLang; }
