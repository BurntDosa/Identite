#!/usr/bin/env python3
"""Export Cardy's Large parts. Python 3 standard library only; never persist the token."""
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import hashlib
import json
import math
import re
import struct
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
import zlib

FILE = "PJKGrFdqh2AHfCezlYM518"
SET = "1457:1695"
OUT = Path(__file__).resolve().parents[1] / "cardy"
ROLES = ("background", "primary", "secondary", "accent")
NAMES = {"base": ("Background", "Background/Gradiant", "Gradient", "Back"),
         "pattern": ("Pattern", "Mask", "Mask group"),
         "shape": ("Shape", "Shapes", "Second Shape"), "texture": ("Noise",),
         "overlay": ("Overlay",), "illustration": ("Illustration",),
         "object3d": ("3D Object",)}
WRAPPERS = {"Right Side", "Top side", "Bottom side", "Card", "Large", "Large /  27"}
CACHE = None


def walk(node):
    yield node
    for child in node.get("children", []):
        yield from walk(child)


def excluded(node):
    return node["type"] == "TEXT" or node["name"].lower() in {"logo", "left side", "text"}


def art_nodes(node):
    if excluded(node):
        return []
    if ((node["name"] in WRAPPERS and node.get("children")) or
            any(excluded(n) for n in walk(node))):
        return [a for c in node.get("children", []) for a in art_nodes(c)]
    return [node]


def category(name):
    for group, names in NAMES.items():
        if name in names:
            return group
    return "shape" if name.startswith("Ellipse ") else "pattern"


def hex_color(c):
    return "#" + "".join(f"{round(c[k] * 255):02X}" for k in ("r", "g", "b"))


def rank_roles(areas):
    # More than four original paints share accent after the three largest areas.
    return {c: ROLES[min(i, 3)] for i, c in enumerate(sorted(areas, key=lambda c: (-areas[c], c)))}


def get(url, token=None):
    cached = CACHE / hashlib.sha256(url.encode()).hexdigest() if CACHE and not token else None
    if cached and cached.exists():
        return cached.read_bytes()
    headers = {"X-Figma-Token": token} if token else {}
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=120) as response:
            data = response.read()
            if cached: cached.write_bytes(data)
            return data
    except urllib.error.HTTPError as error:
        # Response bodies/headers can contain credentials or expiring signed URLs.
        raise RuntimeError(f"Download failed: HTTP {error.code}; no credentials logged") from None


def api(path, token, **query):
    url = "https://api.figma.com/v1/" + path + "?" + urllib.parse.urlencode(query)
    cached = CACHE / (hashlib.sha256(url.encode()).hexdigest() + ".json") if CACHE else None
    if cached and cached.exists():
        return json.loads(cached.read_text())
    data = get(url, token)
    if cached: cached.write_bytes(data)
    return json.loads(data)


def rgba_png(data):
    """Decode Figma's non-interlaced 8-bit PNGs without an imaging dependency."""
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "Expected PNG"
    pos, packed, palette, transparency = 8, b"", [], b""
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        payload = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            width, height, depth, mode, _, _, interlace = struct.unpack(">IIBBBBB", payload)
        elif kind == b"IDAT":
            packed += payload
        elif kind == b"PLTE":
            palette = [tuple(payload[i:i + 3]) for i in range(0, len(payload), 3)]
        elif kind == b"tRNS":
            transparency = payload
        pos += length + 12
    assert depth == 8 and interlace == 0, "Unsupported PNG depth/interlace"
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[mode]
    stride = width * channels
    raw, prev, result = zlib.decompress(packed), bytearray(stride), bytearray()
    for y in range(height):
        start = y * (stride + 1)
        filt, row = raw[start], bytearray(raw[start + 1:start + 1 + stride])
        for x in range(stride):
            a, b, c = (row[x - channels] if x >= channels else 0), prev[x], (prev[x - channels] if x >= channels else 0)
            if filt == 1: predictor = a
            elif filt == 2: predictor = b
            elif filt == 3: predictor = (a + b) // 2
            elif filt == 4:
                p = a + b - c
                predictor = min((a, b, c), key=lambda v: abs(p - v))
            else:
                assert filt == 0
                predictor = 0
            row[x] = (row[x] + predictor) & 255
        for x in range(0, stride, channels):
            if mode == 6: pixel = row[x:x + 4]
            elif mode == 2: pixel = (*row[x:x + 3], 255)
            elif mode == 3:
                index = row[x]
                pixel = (*palette[index], transparency[index] if index < len(transparency) else 255)
            elif mode == 4: pixel = (row[x], row[x], row[x], row[x + 1])
            else: pixel = (row[x], row[x], row[x], 255)
            result.extend(pixel)
        prev = row
    return width, height, result


def paint_areas(data, fills):
    _, _, pixels = rgba_png(data)
    colors = {c: tuple(int(c[i:i + 2], 16) for i in (1, 3, 5)) for c in fills}
    histogram = Counter(tuple(pixels[i:i + 4]) for i in range(0, len(pixels), 4) if pixels[i + 3])
    counts = dict.fromkeys(fills, 0.0)
    for pixel, count in histogram.items():
        nearest = min(colors, key=lambda c: sum((pixel[i] - colors[c][i]) ** 2 for i in range(3)))
        counts[nearest] += count * pixel[3] / 255
    return counts


def encode_png(width, height, pixels):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    scanlines = b"".join(b"\0" + pixels[y * width * 4:(y + 1) * width * 4] for y in range(height))
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(scanlines, 9)) + chunk(b"IEND", b"")


def image_mask(node, token):
    """A painted mask cannot be exported alone; reconstruct its original tiled fill."""
    fill = next(f for f in node["fills"] if f["type"] == "IMAGE")
    assert fill["scaleMode"] == "TILE"
    urls = api(f"files/{FILE}/images", token)["meta"]["images"]
    iw, ih, source = rgba_png(get(urls[fill["imageRef"]]))
    base = next(f for f in node["fills"] if f["type"] == "SOLID")["color"]
    background = [round(base[k] * 255) for k in ("r", "g", "b")]
    box, scale, radius = node["absoluteBoundingBox"], fill["scalingFactor"], node.get("cornerRadius", 0)
    width, height = round(box["width"] * 4), round(box["height"] * 4)
    pixels = bytearray(width * height * 4)
    for y in range(height):
        for x in range(width):
            px, py = (x + .5) / 4, (y + .5) / 4
            cx, cy = min(max(px, radius), box["width"] - radius), min(max(py, radius), box["height"] - radius)
            if (px - cx) ** 2 + (py - cy) ** 2 > radius ** 2: continue
            sx, sy = (px / scale) % iw, (py / scale) % ih
            x0, y0 = math.floor(sx), math.floor(sy)
            samples = [(x0, y0, (1-sx%1)*(1-sy%1)), (x0+1, y0, (sx%1)*(1-sy%1)),
                       (x0, y0+1, (1-sx%1)*(sy%1)), (x0+1, y0+1, (sx%1)*(sy%1))]
            rgba = [sum(source[((yy%ih)*iw+xx%iw)*4+k]*weight for xx,yy,weight in samples) for k in range(4)]
            alpha = rgba[3] / 255 * fill.get("opacity", 1)
            i = (y * width + x) * 4
            pixels[i:i+4] = bytes([round(rgba[k]*alpha+background[k]*(1-alpha)) for k in range(3)]+[255])
    return encode_png(width, height, pixels)


def svg_colors(data):
    root = ET.fromstring(data)
    colors = set()
    def painted(el):
        if el.tag.split("}")[-1] in ("mask", "clipPath", "filter"):
            return
        yield el
        for child in el: yield from painted(child)
    for el in painted(root):
        assert el.tag.split("}")[-1] not in ("text", "image"), "Unexpected text/image in vector export"
        for name in ("fill", "stroke", "stop-color", "flood-color"):
            value = el.get(name, "")
            if value in ("white", "black"):
                value = {"white": "#FFFFFF", "black": "#000000"}[value]
            if re.fullmatch(r"#[0-9A-Fa-f]{3}", value):
                value = "#" + "".join(c * 2 for c in value[1:])
            if re.fullmatch(r"#[0-9A-Fa-f]{6}", value):
                colors.add(value.upper())
    return sorted(colors)


def hidden_rectangles(node):
    """Restore the sole hidden Shape from REST paths; do not change the Figma file."""
    box = node["absoluteBoundingBox"]
    elements, rects, fills = [], [], set()
    for index, child in enumerate(node["children"]):
        assert child["type"] == "RECTANGLE" and not child["fills"] and not child["effects"]
        a, b = child["relativeTransform"]
        matrix = f"{a[0]} {b[0]} {a[1]} {b[1]} {a[2]} {b[2]}"
        path = child["fillGeometry"][0]["path"]
        ink, opacity = hex_color(child["strokes"][0]["color"]), child.get("opacity", 1)
        weight = child["strokeWeight"]
        elements.append(f'<g transform="matrix({matrix})" opacity="{opacity}"><defs><clipPath id="r{index}"><path d="{path}"/></clipPath></defs><path d="{path}" fill="none" stroke="{ink}" stroke-width="{weight * 2}" clip-path="url(#r{index})"/></g>')
        w, h = child["size"]["x"], child["size"]["y"]
        rects.append((a, b, w, h, weight, [int(ink[i:i+2], 16) for i in (1,3,5)], opacity))
        fills.add(ink)
    data = f'<svg xmlns="http://www.w3.org/2000/svg" width="{box["width"]}" height="{box["height"]}" viewBox="0 0 {box["width"]} {box["height"]}">{"".join(elements)}</svg>'
    width, height = math.ceil(box["width"]), math.ceil(box["height"])
    pixels = bytearray(width * height * 4)
    for y in range(height):
        for x in range(width):
            rgb, alpha = [0.0, 0.0, 0.0], 0.0
            for a, b, w, h, weight, ink, opacity in rects:
                px, py = (x+.5)*box["width"]/width-a[2], (y+.5)*box["height"]/height-b[2]
                determinant = a[0]*b[1]-a[1]*b[0]
                u, v = (px*b[1]-a[1]*py)/determinant, (a[0]*py-px*b[0])/determinant
                if 0 <= u <= w and 0 <= v <= h and min(u,v,w-u,h-v) < weight:
                    combined = opacity + alpha*(1-opacity)
                    rgb = [(ink[i]*opacity+rgb[i]*alpha*(1-opacity))/combined for i in range(3)]
                    alpha = combined
            i = (y*width+x)*4
            pixels[i:i+4] = bytes([round(c) for c in rgb]+[round(alpha*255)])
    return data.encode(), paint_areas(encode_png(width,height,pixels), sorted(fills))


def main():
    global CACHE
    token = (Path.home() / ".figma-token").read_text().strip()
    assert token, "Figma token is empty"
    response = api(f"files/{FILE}/nodes", token, ids=SET)
    CACHE = Path(tempfile.gettempdir()) / ("identite-cardy-" + hashlib.sha256(str(response.get("version")).encode()).hexdigest()[:12])
    CACHE.mkdir(exist_ok=True)
    variants = response["nodes"][SET]["document"]["children"]
    assert len(variants) == 30, "Large variant count changed"
    manifest, jobs, audit = [], [], []
    for variant in sorted(variants, key=lambda v: int(v["name"].split("=")[-1])):
        number = variant["name"].split("=")[-1]
        canvas = variant
        if len(variant["children"]) == 1 and variant["children"][0]["name"] in WRAPPERS:
            canvas = variant["children"][0]
        box = variant["absoluteBoundingBox"]
        entry = {"variant": number, "figmaId": variant["id"], "size": [box["width"], box["height"]], "layers": []}
        target = OUT / "parts" / number
        target.mkdir(parents=True, exist_ok=True)
        fills = [f for f in canvas.get("fills", []) if f.get("visible", True)]
        if fills:
            assert len(fills) == 1 and fills[0]["type"] == "SOLID"
            fill = hex_color(fills[0]["color"])
            data = f'<svg xmlns="http://www.w3.org/2000/svg" width="311" height="200" viewBox="0 0 311 200"><rect width="311" height="200" fill="{fill}"/></svg>'.encode()
            path = target / "background-fill.svg"
            path.write_bytes(data)
            entry["layers"].append({"id": f"cardy.{number}.background-fill", "name": "Background (canvas fill)",
                "figmaId": canvas["id"], "category": "base", "file": str(path.relative_to(OUT)), "kind": "vector",
                "fills": [fill], "roleMap": {fill: "background"}, "fillArea": {fill: 62200},
                "areaMethod": "exact solid canvas area", "bounds": [0, 0, 1, 1], "source": "REST canvas fill", "visible": True})
        nodes = [n for c in canvas["children"] for n in art_nodes(c)]
        # Keep the literal placeholder as required, and expose its named 3D child too.
        for n in list(nodes):
            if "3D Object" in n["name"] and n["name"] != "3D Object":
                nodes += [c for c in n.get("children", []) if c["name"] == "3D Object"]
        names = Counter()
        for node in nodes:
            slug = re.sub(r"[^a-z0-9]+", "-", node["name"].lower()).strip("-")
            names[slug] += 1
            if names[slug] > 1: slug += f'-{names[slug]}'
            image = any(f["type"] == "IMAGE" and f.get("visible", True) for n in walk(node) for f in n.get("fills", []))
            bounds = node["absoluteBoundingBox"]
            layer = {"id": f"cardy.{number}.{slug}", "name": node["name"], "figmaId": node["id"],
                "category": category(node["name"]), "file": f'parts/{number}/{slug}.{"png" if image else "svg"}',
                "kind": "image" if image else "vector", "fills": [], "roleMap": {},
                "bounds": [round((bounds["x"] - box["x"]) / box["width"], 8), round((bounds["y"] - box["y"]) / box["height"], 8),
                           round(bounds["width"] / box["width"], 8), round(bounds["height"] / box["height"], 8)],
                "visible": node.get("visible", True), "blendMode": node.get("blendMode", "NORMAL"),
                "opacity": node.get("opacity", 1)}
            if node.get("isMask"): layer["isMask"] = True
            if node["name"] not in sum((list(v) for v in NAMES.values()), []) and not node["name"].startswith("Ellipse "):
                layer["categoryFallback"] = True
            # Visual audit: variant 7 is the holographic foil; other image gradients keep their colours.
            if image and number == "7" and node["name"] == "Gradients":
                layer["tint"] = "blend"
            if node["name"] == "3D Object": layer["alsoContainedIn"] = f"cardy.{number}.paste-your-3d-object-here"
            entry["layers"].append(layer)
            jobs.append((node, layer))
        audit.append({"variant": number, "canvasId": canvas["id"],
                      "artNodeIds": [n["id"] for n in nodes],
                      "excluded": [{"figmaId": n["id"], "reason": "TEXT" if n["type"] == "TEXT" else n["name"]}
                                   for n in walk(canvas) if excluded(n)]})
        manifest.append(entry)
    print("30 variants", flush=True)
    for image in (False, True):
        group = [(n, l) for n, l in jobs if (l["kind"] == "image") == image and l["visible"] and not l.get("isMask")]
        for start in range(0, len(group), 12):
            batch = group[start:start + 12]
            ids = ",".join(n["id"] for n, _ in batch)
            urls = api(f"images/{FILE}", token, ids=ids, format="png" if image else "svg", scale=4 if image else 1,
                       use_absolute_bounds="true", svg_outline_text="false", svg_include_node_id="false")["images"]
            with ThreadPoolExecutor(max_workers=4) as pool:
                payloads = list(pool.map(lambda item: get(urls[item[0]["id"]]) if urls.get(item[0]["id"]) else None, batch))
            samples = {}
            if not image:
                sample_urls = api(f"images/{FILE}", token, ids=ids, format="png", scale=1, use_absolute_bounds="true")["images"]
                with ThreadPoolExecutor(max_workers=4) as pool:
                    sample_data = list(pool.map(lambda item: get(sample_urls[item[0]["id"]]), batch))
                samples = dict(zip((n["id"] for n, _ in batch), sample_data))
            for (node, layer), data in zip(batch, payloads):
                assert data, f'Figma returned no render for {layer["id"]}'
                (OUT / layer["file"]).write_bytes(data)
                if not image:
                    layer["fills"] = svg_colors(data)
                    areas = paint_areas(samples[node["id"]], layer["fills"])
                    layer["fillArea"] = {c: round(a, 4) for c, a in areas.items()}
                    layer["areaMethod"] = "alpha-weighted 1x PNG pixels; nearest original sRGB paint (gradient stops included)"
                    layer["roleMap"] = rank_roles(areas)
            print(f'  exported {min(start + 12, len(group))}/{len(group)} {"image" if image else "vector"} layers', flush=True)
    for node, layer in jobs:
        if layer.get("isMask"):
            assert node["type"] == "RECTANGLE"
            if layer["kind"] == "image":
                (OUT / layer["file"]).write_bytes(image_mask(node, token))
                layer.update(source="REST image-fill tile reconstruction (painted mask export returns null)", exportScale=4)
                continue
            assert len(node["fills"]) == 1 and node["fills"][0]["type"] == "SOLID"
            ink = hex_color(node["fills"][0]["color"])
            w, h = node["absoluteBoundingBox"]["width"], node["absoluteBoundingBox"]["height"]
            (OUT / layer["file"]).write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}"><rect width="{w}" height="{h}" fill="{ink}"/></svg>')
            layer.update(fills=[ink], roleMap={ink: "background"}, fillArea={ink: w*h}, areaMethod="exact rectangular mask area", source="REST mask geometry (isolated mask export returns null)")
        elif not layer["visible"]:
            geometry = api(f"files/{FILE}/nodes", token, ids=node["id"], geometry="paths")["nodes"][node["id"]]["document"]
            data, areas = hidden_rectangles(geometry)
            (OUT / layer["file"]).write_bytes(data)
            layer.update(fills=sorted(areas), roleMap=rank_roles(areas), fillArea=areas,
                         areaMethod="hidden: 1x raster of transformed inside strokes; painter order and alpha; nearest original sRGB paint",
                         source="REST geometry reconstruction (hidden node export returns null)")
    for variant in manifest:
        for layer in variant["layers"]:
            layer["sha256"] = hashlib.sha256((OUT / layer["file"]).read_bytes()).hexdigest()
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    (OUT / "source-inventory.json").write_text(json.dumps({"file": FILE, "componentSet": SET, "version": response.get("version"),
        "credit": "Card designs include elements from Cardy by Piqo Design.", "variants": audit}, indent=2) + "\n")
    counts = Counter(l["category"] for v in manifest for l in v["layers"])
    for name in NAMES:
        print(f"{name}: {counts[name]}")


def self_check():
    tree = {"id": "wrapper", "name": "Top side", "type": "GROUP", "children": [
        {"id": "art", "name": "Pattern", "type": "RECTANGLE"},
        {"id": "text", "name": "Example", "type": "TEXT"},
        {"id": "logo", "name": "Logo", "type": "INSTANCE"}]}
    assert [n["id"] for n in art_nodes(tree)] == ["art"]
    assert category("Background/Gradiant") == "base"
    assert category("Ellipse 23") == "shape"
    assert category("Unknown") == "pattern"
    assert rank_roles({"#111111": 30, "#FFFFFF": 60}) == {
        "#FFFFFF": "background", "#111111": "primary"}
    pixels = bytes([255, 0, 0, 255, 0, 0, 255, 128])
    assert rgba_png(encode_png(2, 1, pixels)) == (2, 1, pixels)
    assert svg_colors(b'<svg><defs><mask><path fill="white"/></mask></defs><path fill="#ABC"/></svg>') == ["#AABBCC"]
    print("Exporter self-check passed")


if __name__ == "__main__":
    if "--self-check" in sys.argv:
        self_check()
    else:
        main()
