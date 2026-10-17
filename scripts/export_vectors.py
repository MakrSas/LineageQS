#!/usr/bin/env python3
"""Export Android VectorDrawable / AnimatedVectorDrawable resources to compact JSON.

Runs on s8build against the apktool-decoded SystemUI resources. For an
<animated-vector> the *final* frame is exported: every objectAnimator's
valueTo (or the last keyframe) is applied to the named path/group. That is the
resting "on"/"off" appearance the tile shows after its state animation.

Output per icon:
  {"name", "source", "viewport":[w,h], "size":[dpW,dpH],
   "nodes":[{"type":"group", "transform":{...}, "children":[...]} |
            {"type":"path", "d", "fill", "fillAlpha", "fillType",
             "stroke", "strokeWidth", "strokeAlpha", "trim":[start,end,offset],
             "lineCap", "lineJoin"} |
            {"type":"clip", "d"}]}
Colors are emitted as "#AARRGGBB" when literal, otherwise the unresolved
reference string (e.g. "@color/foo" or "?attr/..."); the iOS renderer tints
icons as templates and only uses alpha.

Usage: export_vectors.py RES_DIR OUT_DIR name [name...]
"""
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

A = "{http://schemas.android.com/apk/res/android}"
RES = sys.argv[1]
OUT = sys.argv[2]
NAMES = sys.argv[3:]

_strings = None
_colors = None


def strings():
    global _strings
    if _strings is None:
        _strings = {}
        # strings.xml plus any other values/*.xml holding <string> (AOSP keeps
        # vector path data in values/paths.xml).
        vdir = os.path.join(RES, "values")
        for fn in sorted(os.listdir(vdir)):
            if not fn.endswith(".xml"):
                continue
            try:
                root = ET.parse(os.path.join(vdir, fn)).getroot()
            except ET.ParseError:
                continue
            for el in root:
                if el.tag == "string" and el.get("name"):
                    _strings[el.get("name")] = "".join(el.itertext())
    return _strings


def colors():
    global _colors
    if _colors is None:
        _colors = {}
        for sub in ("values", "values-night"):
            p = os.path.join(RES, sub, "colors.xml")
            if os.path.exists(p):
                # apktool output is not always well-formed XML; read entries by regex.
                text = open(p, encoding="utf-8", errors="replace").read()
                for name, val in re.findall(r'<color name="([^"]+)">([^<]*)</color>', text):
                    _colors[(sub, name)] = val.strip()
    return _colors


def resolve_string(v):
    if v and v.startswith("@string/"):
        return strings().get(v[8:], v)
    return v


def resolve_color(v, depth=0):
    if not v:
        return None
    if v.startswith("#"):
        h = v[1:]
        if len(h) == 6:
            h = "ff" + h
        elif len(h) == 3:
            h = "ff" + "".join(c * 2 for c in h)
        elif len(h) == 4:
            h = "".join(c * 2 for c in h)
        return "#" + h.lower()
    if v.startswith("@color/") and depth < 8:
        name = v[7:]
        c = colors()
        val = c.get(("values-night", name)) or c.get(("values", name))
        if val:
            return resolve_color(val, depth + 1)
    return v


def fnum(v, d=None):
    if v is None:
        return d
    try:
        return float(str(v).replace("dip", "").replace("dp", "").replace("px", ""))
    except ValueError:
        return d


def drawable_path(name):
    p = os.path.join(RES, "drawable", name + ".xml")
    if os.path.exists(p):
        return p
    raise FileNotFoundError(name)


def ref_name(v):
    return v.split("/", 1)[1] if v and "/" in v else v

AAPT = "{http://schemas.android.com/aapt}attr"


def inline_attr(el, key):
    """Child <aapt:attr name="android:KEY"> -> its first element (inline resource)."""
    for c in el:
        if c.tag == AAPT and c.get("name") == "android:" + key:
            kids = list(c)
            return kids[0] if kids else None
    return None


def res_root(ref, subs=("animator", "anim", "drawable")):
    name = ref_name(ref)
    for sub in subs:
        p = os.path.join(RES, sub, name + ".xml")
        if os.path.exists(p):
            return ET.parse(p).getroot()
    raise FileNotFoundError(name)


def interp_from_element(el):
    if el.tag == "pathInterpolator":
        if el.get(A + "pathData"):
            d = el.get(A + "pathData")
            nums = [float(x) for x in re.findall(r"-?\d*\.?\d+(?:e-?\d+)?", d)]
            if d.strip().lower().startswith("m") and " c" in d.lower() and len(nums) == 8:
                return {"cubic": nums[2:6]}
            return {"path": d}
        if el.get(A + "controlX2") is not None:
            return {"cubic": [float(el.get(A + k)) for k in ("controlX1", "controlY1", "controlX2", "controlY2")]}
        return {"quad": [float(el.get(A + "controlX1")), float(el.get(A + "controlY1"))]}
    return {"name": el.tag}


_INTERP_CACHE = {}


def resolve_interpolator(ref):
    """@anim/x or @drawable/$$..__0 -> {"cubic":[x1,y1,x2,y2]} | {"path": d} | {"name": ...}."""
    if not ref:
        return {"name": "accelerateDecelerate"}  # Android ValueAnimator default
    if ref in _INTERP_CACHE:
        return _INTERP_CACHE[ref]
    kind, name = ref[1:].split("/", 1) if "/" in ref else ("", ref)
    out = {"name": name}
    for sub in ([kind] if kind else []) + ["anim", "interpolator", "drawable"]:
        p = os.path.join(RES, sub, name + ".xml")
        if not os.path.exists(p):
            continue
        el = ET.parse(p).getroot()
        if el.tag == "pathInterpolator":
            if el.get(A + "pathData"):
                d = el.get(A + "pathData")
                nums = [float(x) for x in re.findall(r"-?\d*\.?\d+(?:e-?\d+)?", d)]
                # "M 0,0 c x1,y1 x2,y2 1,1" (relative) -> cubic control points
                if d.strip().lower().startswith("m") and " c" in d.lower() and len(nums) == 8:
                    out = {"cubic": nums[2:6]}
                else:
                    out = {"path": d}
            elif el.get(A + "controlX2") is not None:
                out = {"cubic": [float(el.get(A + k)) for k in ("controlX1", "controlY1", "controlX2", "controlY2")]}
            else:
                out = {"quad": [float(el.get(A + "controlX1")), float(el.get(A + "controlY1"))]}
        else:
            out = {"name": el.tag}
        break
    _INTERP_CACHE[ref] = out
    return out


def path_end_point(d):
    """End point of a (motion) path; supports M/L/C/H/V/Z absolute+relative."""
    toks = re.findall(r"[MmLlHhVvCcSsQqTtAaZz]|-?\d*\.?\d+(?:e-?\d+)?", d)
    x = y = 0.0
    sx = sy = 0.0
    cmd = None
    i = 0
    arity = {"M": 2, "L": 2, "T": 2, "H": 1, "V": 1, "C": 6, "S": 4, "Q": 4, "A": 7, "Z": 0}
    while i < len(toks):
        t = toks[i]
        if t.isalpha():
            cmd = t
            i += 1
            if cmd in "Zz":
                x, y = sx, sy
            continue
        n = arity[cmd.upper()]
        vals = [float(v) for v in toks[i:i + n]]
        i += n
        rel = cmd.islower()
        u = cmd.upper()
        if u == "H":
            x = x + vals[0] if rel else vals[0]
        elif u == "V":
            y = y + vals[0] if rel else vals[0]
        else:
            nx, ny = vals[-2], vals[-1]
            x, y = (x + nx, y + ny) if rel else (nx, ny)
        if u == "M":
            sx, sy = x, y
            cmd = "l" if rel else "L"
    return x, y


def animators(root):
    """Flattened animator list with absolute start offsets."""
    out = []

    def visit(el, base_offset):
        seq = el.tag == "set" and el.get(A + "ordering") == "sequentially"
        offset = base_offset
        children = list(el) if el.tag == "set" else [el]
        for child in children:
            if child.tag == "set":
                end = visit(child, offset)
                if seq:
                    offset = end
                continue
            if child.tag != "objectAnimator":
                continue
            start = offset + fnum(child.get(A + "startOffset"), 0)
            dur = fnum(child.get(A + "duration"), 300)
            ie = inline_attr(child, "interpolator")
            interp = interp_from_element(ie) if ie is not None else resolve_interpolator(child.get(A + "interpolator"))
            prop = child.get(A + "propertyName")
            entry = {"start": start, "duration": dur, "interp": interp}
            if prop == "translateXY" or child.get(A + "pathData"):
                entry.update({"prop": "translateXY", "path": child.get(A + "pathData")})
            elif prop:
                vf, vt = child.get(A + "valueFrom"), child.get(A + "valueTo")
                vtype = child.get(A + "valueType") or ("pathType" if prop == "pathData" else "floatType")
                conv = (lambda v: resolve_string(v)) if vtype == "pathType" else (lambda v: resolve_color(v) if (v or "").startswith(("#", "@color")) else fnum(v))
                entry.update({"prop": prop, "from": conv(vf) if vf is not None else None, "to": conv(vt) if vt is not None else None})
            else:
                for pvh in child.iter("propertyValuesHolder"):
                    kfs = [{"f": fnum(k.get(A + "fraction"), 0), "v": fnum(k.get(A + "value"))} for k in pvh.iter("keyframe")]
                    out.append(dict(entry, prop=pvh.get(A + "propertyName"), keyframes=kfs,
                                    **({"from": fnum(pvh.get(A + "valueFrom")), "to": fnum(pvh.get(A + "valueTo"))} if not kfs else {})))
                if seq:
                    offset = start + dur
                continue
            out.append(entry)
            if seq:
                offset = start + dur
        return offset

    visit(root, 0)
    return out


def final_values(root):
    """Return {propertyName: finalValue} for an animator xml (set/objectAnimator)."""
    best = {}

    def visit(el, base_offset, sequential):
        offset = base_offset
        for child in list(el) if el.tag == "set" else [el]:
            if child.tag == "set":
                seq = child.get(A + "ordering") == "sequentially"
                end = visit(child, offset, seq)
                if sequential:
                    offset = end
                continue
            if child.tag != "objectAnimator":
                continue
            start = offset + fnum(child.get(A + "startOffset"), 0)
            end = start + fnum(child.get(A + "duration"), 300)
            props = []
            if child.get(A + "pathData") and child.get(A + "propertyName") == "translateXY":
                ex, ey = path_end_point(child.get(A + "pathData"))
                props.append(("translateX", str(ex), None))
                props.append(("translateY", str(ey), None))
            elif child.get(A + "propertyName"):
                props.append((child.get(A + "propertyName"), child.get(A + "valueTo"), child.get(A + "valueFrom")))
            for pvh in child.iter("propertyValuesHolder"):
                kfs = list(pvh.iter("keyframe"))
                val = kfs[-1].get(A + "value") if kfs else pvh.get(A + "valueTo")
                props.append((pvh.get(A + "propertyName"), val, pvh.get(A + "valueFrom")))
            for prop, to, frm in props:
                val = to if to is not None else frm
                if prop and val is not None and (prop not in best or best[prop][0] <= end):
                    best[prop] = (end, val)
            if sequential:
                offset = end
        return offset

    visit(root, 0, False)
    return {k: v[1] for k, v in best.items()}


def export(name):
    root = ET.parse(drawable_path(name)).getroot()
    overrides = {}
    anims = {}
    source = ["res/drawable/%s.xml" % name]
    if root.tag == "animated-vector":
        base_el = inline_attr(root, "drawable")
        for t in root.iter("target"):
            ae = inline_attr(t, "animation")
            if ae is None:
                ae = res_root(t.get(A + "animation"))
                source.append("res/%s" % ref_name(t.get(A + "animation")))
            overrides.setdefault(t.get(A + "name"), {}).update(final_values(ae))
            anims.setdefault(t.get(A + "name"), []).extend(animators(ae))
        if base_el is None:
            base = ref_name(root.get(A + "drawable"))
            source.append("res/drawable/%s.xml" % base)
            base_el = ET.parse(drawable_path(base)).getroot()
        root = base_el
    if root.tag != "vector":
        raise ValueError("%s: unsupported root %s" % (name, root.tag))

    use_overrides = [True]

    def attr(el, key, default=None):
        o = overrides.get(el.get(A + "name"), {}) if use_overrides[0] else {}
        if key in o:
            return o[key]
        return el.get(A + key, default)

    def node(el):
        if el.tag == "group":
            tr = {k: fnum(attr(el, k)) for k in ("rotation", "pivotX", "pivotY", "scaleX", "scaleY", "translateX", "translateY") if attr(el, k) is not None}
            return {"type": "group", "name": el.get(A + "name"), "transform": tr, "children": [n for n in (node(c) for c in el) if n]}
        if el.tag == "clip-path":
            return {"type": "clip", "d": resolve_string(attr(el, "pathData"))}
        if el.tag == "path":
            n = {"type": "path", "name": el.get(A + "name"), "d": resolve_string(attr(el, "pathData"))}
            for k in ("fillColor", "strokeColor"):
                if attr(el, k):
                    n[k.replace("Color", "")] = resolve_color(attr(el, k))
            for k in ("fillAlpha", "strokeAlpha", "strokeWidth", "trimPathStart", "trimPathEnd", "trimPathOffset"):
                if attr(el, k) is not None:
                    n[k] = fnum(attr(el, k))
            for k in ("fillType", "strokeLineCap", "strokeLineJoin"):
                if attr(el, k):
                    n[k] = attr(el, k)
            return n
        return None

    data = {
        "name": name,
        "source": source,
        "viewport": [fnum(root.get(A + "viewportWidth")), fnum(root.get(A + "viewportHeight"))],
        "size": [fnum(root.get(A + "width")), fnum(root.get(A + "height"))],
        "alpha": fnum(root.get(A + "alpha"), 1.0),
        "nodes": [n for n in (node(c) for c in root) if n],
    }
    if anims:
        # Base (un-animated) tree + animators: the iOS renderer replays the
        # AnimatedVectorDrawable; "nodes" stays the final frame for static use.
        use_overrides[0] = False
        data["base"] = [n for n in (node(c) for c in root) if n]
        data["anims"] = anims
        data["animDuration"] = max((a["start"] + a["duration"]) for lst in anims.values() for a in lst)
    return data


def main():
    os.makedirs(OUT, exist_ok=True)
    ok = 0
    for name in NAMES:
        try:
            data = export(name)
        except Exception as exc:  # report and continue; caller decides
            print("FAIL %s: %s" % (name, exc))
            continue
        with open(os.path.join(OUT, name + ".json"), "w") as fh:
            json.dump(data, fh, separators=(",", ":"))
        ok += 1
        print("OK %s" % name)
    print("exported %d/%d" % (ok, len(NAMES)))


if __name__ == "__main__":
    main()
