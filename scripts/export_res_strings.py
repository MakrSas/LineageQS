#!/usr/bin/env python3
"""Export SystemUI translations keyed by Android resource name.

Usage: export_res_strings.py OUT_DIR RES_DIR [RES_DIR...]  (later dirs override earlier)
Writes OUT/<lang>.json ({"resource_name": "text"}); "en" comes from values/.
Only names matching PREFIXES are kept. Android format args (%s, %1$s) become %@.
"""
import json, os, re, sys
import xml.etree.ElementTree as ET

OUT, RES = sys.argv[1], sys.argv[2:]
PREFIXES = ("quick_settings_", "qs_", "accessibility_quick_settings_", "state_", "brightness", "accessibility_brightness",
            "tile_", "accessibility_desc_quick_settings", "notification_section_header", "clear_all_notifications_text",
            "no_notifications", "empty_shade_text", "manage_notifications_text", "status_bar_settings_", "accessibility_wifi_",
            "accessibility_bluetooth", "accessibility_battery", "accessibility_data_", "wifi_", "battery_detail_", "data_saver",
            "screenrecord_", "qr_code_scanner", "wallet_", "dnd_", "zen_", "global_action_", "media_", "controls_",
            "internet_dialog_", "mobile_data", "airplane_mode", "status_bar_alarm", "quick_controls_title", "controls_tile", "keyguard_", "tile_states_", "see_all", "switch_bar_", "accessibility_quick_settings_", "select_to_", "tap_to_position", "tile_already", "action_bar_up", "keyguard_missing_sim", "cast_", "abc_", "lockscreen_",
            "accessibility_quick_settings", "edit_", "drag_", "unavailable", "save", "clear")
FMT = re.compile(r"%(\d+\$)?s")


def clean(el):
    t = "".join(el.itertext())
    t = t.replace("\\'", "'").replace('\\"', '"').replace("\\n", "\n").strip()
    if len(t) >= 2 and t[0] == '"' and t[-1] == '"':
        t = t[1:-1]
    return FMT.sub(lambda m: "%" + (m.group(1) or "") + "@", t)


def load(d):
    out = {}
    for fn in ("strings.xml", "lineage_strings.xml", "cm_strings.xml", "tiles_states_strings.xml"):
        p = os.path.join(d, fn)
        if not os.path.exists(p):
            continue
        root = ET.parse(p).getroot()
        for el in root.iter("string"):
            n = el.get("name")
            if n and n.startswith(PREFIXES):
                out[n] = clean(el)
        # <string-array name="tile_states_x"> -> tile_states_x_0 (unavailable), _1 (off), _2 (on)
        for arr in root.iter("string-array"):
            n = arr.get("name")
            if n and n.startswith(PREFIXES):
                for i, it in enumerate(arr.iter("item")):
                    out["%s_%d" % (n, i)] = clean(it)
    return out


langs = {}
for res in RES:
    for sub in sorted(os.listdir(res)):
        if sub == "values":
            lang = "en"
        elif re.fullmatch(r"values-[a-z]{2,3}(-r[A-Z]{2}|-b\+[A-Za-z+]+)?", sub):
            lang = sub[7:].replace("-r", "-")
        else:
            continue
        langs.setdefault(lang, {}).update(load(os.path.join(res, sub)))
# Resolve "@string/x" references against the same language, then English.
for lang, m in langs.items():
    for k, v in list(m.items()):
        if v.startswith("@string/"):
            ref = v[8:]
            m[k] = m.get(ref) or langs["en"].get(ref) or v
os.makedirs(OUT, exist_ok=True)
for lang, m in langs.items():
    if m:
        json.dump(m, open(os.path.join(OUT, lang + ".json"), "w"), ensure_ascii=False, separators=(",", ":"), sort_keys=True)
print(len(langs), "languages,", len(langs["en"]), "en strings")
