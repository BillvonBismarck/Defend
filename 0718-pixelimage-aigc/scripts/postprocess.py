#\!/usr/bin/env python3
"""Pixel asset post-processing pipeline (steps 3-7).

Turns AI-generated high-res drafts into hard-edged, palette-quantized,
integer-scale PNG masters ready for a game runtime.

Pipeline per image:
  3. downscale   -> master size (LANCZOS)
  4. alpha       -> binarize transparent art (or keep layered alpha)
  5. quantize    -> map every opaque pixel to nearest project-palette color
  6. normalize   -> rescale subject bbox to target size and re-center
  7. export      -> master PNG + integer-scale previews + report.json

Usage:
  python3 postprocess.py --input drafts/ --output final/ \
      --master 64 --subject 48 \
      --palette references/palette-project.json \
      --alpha-threshold 128 --scales 1,2,3

  # keep layered alpha (hit fx etc.):
  python3 postprocess.py ... --keep-alpha
"""
import argparse
import json
import os
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("Pillow is required: pip install Pillow")


def hex_to_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def load_palette(path):
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    colors = []
    for v in data.get("shared_neutral", {}).values():
        colors.append(hex_to_rgb(v))
    for ramp in data.get("elements", {}).values():
        for v in ramp:
            colors.append(hex_to_rgb(v))
    # de-dup, keep order
    seen, out = set(), []
    for c in colors:
        if c not in seen:
            seen.add(c)
            out.append(c)
    if not out:
        sys.exit("palette is empty")
    return out


def bbox_of_alpha(img, threshold):
    """Return (left, top, right, bottom) of pixels with alpha > threshold."""
    a = img.getchannel("A")
    mask = a.point(lambda v: 255 if v > threshold else 0)
    bb = mask.getbbox()
    return bb  # None if fully transparent


def nearest_color(px, palette):
    r, g, b = px[0], px[1], px[2]
    best, best_d = palette[0], None
    for c in palette:
        d = (r - c[0]) ** 2 + (g - c[1]) ** 2 + (b - c[2]) ** 2
        if best_d is None or d < best_d:
            best_d, best = d, c
    return best


def quantize(img, palette, threshold):
    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a <= threshold:
                px[x, y] = (0, 0, 0, 0)
            else:
                nr, ng, nb = nearest_color((r, g, b), palette)
                px[x, y] = (nr, ng, nb, 255)
    return img


def normalize_subject(img, subject, threshold):
    """Scale subject bbox to `subject` px (longest side) and re-center on master canvas."""
    bb = bbox_of_alpha(img, threshold)
    if bb is None:
        return img, None
    l, t, r, b = bb
    sw, sh = r - l, b - t
    scale = subject / max(sw, sh)
    nw, nh = max(1, round(sw * scale)), max(1, round(sh * scale))
    subject_img = img.crop((l, t, r, b)).resize((nw, nh), Image.NEAREST)
    canvas = Image.new("RGBA", (img.size[0], img.size[1]), (0, 0, 0, 0))
    ox = (img.size[0] - nw) // 2
    oy = (img.size[1] - nh) // 2
    canvas.paste(subject_img, (ox, oy), subject_img)
    return canvas, (nw, nh, ox, oy)


def count_colors(img, threshold):
    seen = set()
    px = img.load()
    for y in range(img.size[1]):
        for x in range(img.size[0]):
            r, g, b, a = px[x, y]
            if a > threshold:
                seen.add((r, g, b))
    return len(seen)


def process(path, out_dir, args, palette, seen_names):
    base = os.path.basename(path)
    name = os.path.splitext(base)[0]
    # avoid collisions when drafts share a basename (a.png + a.jpg)
    if name in seen_names:
        name = os.path.splitext(base)[0] + "_" + os.path.splitext(base)[1].lstrip(".")
    seen_names.add(name)
    src = Image.open(path).convert("RGBA")

    # 3. downscale to master (square)
    master = src.resize((args.master, args.master), Image.LANCZOS)

    # 4. alpha handling
    if not args.keep_alpha:
        master = quantize(master, palette, args.alpha_threshold)
    else:
        # keep layered alpha but still quantize RGB of opaque-ish pixels
        px = master.load()
        for y in range(args.master):
            for x in range(args.master):
                r, g, b, a = px[x, y]
                if a > args.alpha_threshold:
                    nr, ng, nb = nearest_color((r, g, b), palette)
                    px[x, y] = (nr, ng, nb, a)

    # 6. normalize subject bbox
    norm, info = normalize_subject(master, args.subject, args.alpha_threshold)

    # 7. export master + integer previews
    os.makedirs(out_dir, exist_ok=True)
    master_path = os.path.join(out_dir, name + ".png")
    norm.save(master_path)

    previews = []
    for s in args.scales:
        if s == 1:
            continue
        big = norm.resize((args.master * s, args.master * s), Image.NEAREST)
        p = os.path.join(out_dir, "%s_%dx.png" % (name, s))
        big.save(p)
        previews.append(os.path.relpath(p, out_dir))

    colors = count_colors(norm, args.alpha_threshold)
    issues = []
    if colors > args.max_colors:
        issues.append("colors=%d>%d" % (colors, args.max_colors))
    if info is None:
        issues.append("empty-subject")
    else:
        nw, nh = info[0], info[1]
        if max(nw, nh) < args.subject * 0.75:
            issues.append("subject-too-small")
        if min(nw, nh) == 0:
            issues.append("degenerate-bbox")

    return {
        "file": name + ".png",
        "master": "%dx%d" % (args.master, args.master),
        "subject_bbox": None if info is None else [info[0], info[1]],
        "colors": colors,
        "previews": previews,
        "issues": issues,
    }


def main():
    ap = argparse.ArgumentParser(description="Pixel asset post-processing pipeline")
    ap.add_argument("--input", required=True, help="draft directory")
    ap.add_argument("--output", required=True, help="output directory")
    ap.add_argument("--master", type=int, default=64, help="master canvas size")
    ap.add_argument("--subject", type=int, default=48, help="target subject bbox (longest side)")
    ap.add_argument("--palette", default="references/palette-project.json")
    ap.add_argument("--alpha-threshold", type=int, default=128)
    ap.add_argument("--keep-alpha", action="store_true", help="keep layered alpha (hit fx)")
    ap.add_argument("--max-colors", type=int, default=9)
    ap.add_argument("--scales", default="1,2,3", help="comma-separated integer previews")
    args = ap.parse_args()
    args.scales = [int(s) for s in str(args.scales).split(",") if s.strip()]

    palette = load_palette(args.palette)
    exts = (".png", ".jpg", ".jpeg", ".webp")
    files = sorted(
        os.path.join(args.input, f)
        for f in os.listdir(args.input)
        if f.lower().endswith(exts)
    )
    if not files:
        sys.exit("no images found in " + args.input)

    report, bad = [], 0
    seen_names = set()
    for f in files:
        entry = process(f, args.output, args, palette, seen_names)
        if entry["issues"]:
            bad += 1
        report.append(entry)
        flag = ("  ISSUES: " + ", ".join(entry["issues"])) if entry["issues"] else ""
        print("%-28s colors=%-3d subject=%s%s" % (
            entry["file"], entry["colors"], entry["subject_bbox"], flag))

    rp = os.path.join(args.output, "report.json")
    with open(rp, "w", encoding="utf-8") as fh:
        json.dump({"count": len(report), "flagged": bad, "items": report}, fh,
                  ensure_ascii=False, indent=2)
    print("\n%d/%d images flagged -> %s" % (bad, len(report), rp))


if __name__ == "__main__":
    main()
