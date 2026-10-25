#!/usr/bin/env python3
"""Generate fixed-design paint masks and layer tables from the checked-in Figma exports."""
import hashlib
import json
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'docs/design/cardy'
OUTPUT = ROOT / 'App/Shared/Cards/Composed/CardyParts.xcassets'
CACHE = ROOT / 'build/figma'
RESOURCES = ROOT / 'Packages/IDCore/Sources/IDCore/Resources'
NS = 'http://www.w3.org/2000/svg'
ET.register_namespace('', NS)
W, H = 1024, round(1024 / 1.586)
ROLES = ['background', 'primary', 'secondary', 'accent', 'highlight']
CUBE = ['#000000', '#0000FF', '#00FF00', '#00FFFF', '#FF0000', '#FF00FF', '#FFFF00', '#FFFFFF']
# These source backings bake in the Figma card's outer radius; the app owns that clip.
OUTER_CORNERS = {'cardy.7.gradients': ['top'], 'cardy.13.gradient': ['top'],
                 'cardy.12.overlay': ['bottom'], 'cardy.22.back': ['bottom']}


def canonical(value):
    value = {'white': '#FFFFFF', 'black': '#000000'}.get(value, value)
    if re.fullmatch(r'#[0-9a-fA-F]{3}', value):
        value = '#' + ''.join(c * 2 for c in value[1:])
    return value.upper()


def role_svg(source, paint, bounds, opacity=1, clip=None):
    root = ET.fromstring(source)
    # The standalone export already includes the source node's opacity; the layer table owns it.
    if opacity != 1 and len(root) and 'opacity' in root[0].attrib:
        assert abs(float(root[0].get('opacity')) - opacity) < .001
        root[0].set('opacity', '1')
    # ImageIO treats SVG masks as luminance; white preserves an alpha mask's intended coverage.
    for mask in root.iter():
        if mask.tag.split('}')[-1] == 'mask' and 'alpha' in mask.get('style', ''):
            for element in mask.iter():
                for attr in ('fill', 'stroke', 'stop-color'):
                    if element.get(attr) and canonical(element.get(attr)).startswith('#'):
                        element.set(attr, '#FFFFFF')
    def visit(element):
        if element.tag.split('}')[-1] in ('mask', 'clipPath', 'filter'):
            return
        for attr in ('fill', 'stroke', 'stop-color'):
            value = element.get(attr)
            if value and canonical(value).startswith('#'):
                element.set(attr, '#FFFFFF' if canonical(value) == paint else '#000000')
        for child in element:
            visit(child)
    visit(root)
    x, y, w, h = bounds
    if any(e.tag.split('}')[-1] == 'mask' for e in root.iter()):
        # ImageIO needs the SVG viewport to resolve nested mask coordinates correctly.
        root.set('x', str(x * W)); root.set('y', str(y * H))
        root.set('width', str(w * W)); root.set('height', str(h * H))
        root.set('preserveAspectRatio', 'none')
    else:
        vx, vy, vw, vh = map(float, root.get('viewBox', f'0 0 {root.get("width")} {root.get("height")}').split())
        # A nested SVG viewport clips centered strokes; Figma's explicit clip paths own clipping.
        root.tag = f'{{{NS}}}g'
        for attr in ('viewBox', 'width', 'height', 'x', 'y', 'preserveAspectRatio'):
            root.attrib.pop(attr, None)
        root.set('transform', f'translate({x*W} {y*H}) scale({w*W/vw} {h*H/vh}) translate({-vx} {-vy})')
    inner = ET.tostring(root, encoding='unicode')
    clipdef, clipattr = '', ''
    if clip:
        x, y, w, h = clip
        clipdef = f'<clipPath id="clip"><rect x="{x*W}" y="{y*H}" width="{w*W}" height="{h*H}"/></clipPath>'
        clipattr = ' clip-path="url(#clip)"'
    return (f'<svg xmlns="{NS}" width="{W}" height="{H}" viewBox="0 0 {W} {H}">'
            f'<defs>{clipdef}<mask id="role" maskUnits="userSpaceOnUse" x="0" y="0" width="{W}" height="{H}" style="mask-type:luminance">'
            f'{inner}</mask></defs><rect width="{W}" height="{H}" fill="white" mask="url(#role)"{clipattr}/></svg>')


def leaves(layers):
    for layer in layers:
        if 'children' in layer:
            yield from leaves(layer['children'])
        else:
            yield layer


def blend(value):
    return {'PASS_THROUGH': 'normal', 'NORMAL': 'normal', 'OVERLAY': 'overlay',
            'SOFT_LIGHT': 'softLight', 'MULTIPLY': 'multiply', 'SCREEN': 'screen'}[value]


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True); CACHE.mkdir(parents=True, exist_ok=True)
    (OUTPUT / 'Contents.json').write_text('{"info":{"author":"xcode","version":1}}\n')
    manifest = json.loads((SOURCE / 'manifest.json').read_text())
    jobs, designs = [], {}
    for variant in manifest:
        original = variant['design']['layers']
        # Share colour identities across a design, rather than mapping each isolated layer's largest paint to primary.
        background = next(iter(variant['layers'][0]['roleMap']))
        areas = {}
        for part in leaves(original):
            for color, area in part.get('fillArea', {}).items():
                areas[color] = areas.get(color, 0) + area
        colors = [background] + sorted((c for c in areas if c != background), key=lambda c: (-areas[c], c))
        mapping = {color: ROLES[i] if i < 5 else f'{["primary", "secondary", "accent"][i % 3]}:{(i // 3) * 9 - 18}'
                   for i, color in enumerate(colors)}
        def layer(part):
            ident = part['id']
            d = {'asset': ident, 'kind': part['kind'], 'bounds': part['bounds'],
                 'category': {'cardy.17.pattern-noise': 'texture', 'cardy.6.overlay-bg': 'overlay'}.get(ident, part.get('category')),
                 'outerCorners': OUTER_CORNERS.get(ident, []),
                 'blend': blend(part.get('blendMode', 'NORMAL')), 'opacity': part.get('opacity', 1),
                 'roles': {}, 'toneMapped': '3d-object' in ident, 'masks': {}}
            if 'children' in part:
                d['children'] = [layer(child) for child in part['children']]
                return d
            neutral = part.get('category') == 'texture'
            if part['kind'] == 'vector':
                d['roles'] = {c: mapping[c] for c in part['roleMap']}
                d['roles'].update(part.get('roleOverrides', {}))
            elif not neutral:
                d['roles'] = ({'background': 'background', 'primary': 'primary', 'highlight': 'highlight'} if d['toneMapped']
                              else dict(zip(CUBE, ['accent', 'secondary:12', 'secondary', 'highlight:-12', 'primary', 'primary:14', 'accent:20', 'highlight'])))
            d['roles'].update(part.get('roleOverrides', {}))
            job = {'id': ident, 'masks': {}, 'neutral': None, 'source': str(SOURCE / part['file']),
                   'bounds': part['bounds'], 'clip': part.get('clipBounds'), 'opacity': part.get('opacity', 1),
                   'outerCorners': OUTER_CORNERS.get(ident, []),
                   'mode': 'vector' if part['kind'] == 'vector' else 'neutral' if neutral else 'toneMap' if d['toneMapped'] else 'cube'}
            if neutral:
                job['neutral'] = str(CACHE / (ident + '.png'))
            for paint in d['roles']:
                key = hashlib.sha256((ident + paint).encode()).hexdigest()[:16]
                job['masks'][paint] = str(CACHE / (key + '.png'))
                if job['mode'] == 'vector':
                    source = (SOURCE / part['file']).read_text()
                    if ident == 'cardy.26.back':
                        # One continuous circle outline avoids separately antialiasing its touching halves.
                        root = ET.fromstring(source)
                        right, left = list(root)[6:8]
                        assert right.get('fill') == left.get('fill') == '#546EF3'
                        right.set('d', 'M100 150C100 177.614 77.6142 200 50 200C22.3858 200 0 177.614 0 150C0 122.386 22.3858 100 50 100C77.6142 100 100 122.386 100 150Z')
                        root.remove(left)
                        source = ET.tostring(root, encoding='unicode')
                    svg = role_svg(source, paint, part['bounds'], part.get('opacity', 1), part.get('clipBounds'))
                    path = CACHE / (key + '.svg'); path.write_text(svg)
                    job.setdefault('vectors', {})[paint] = str(path)
            jobs.append(job)
            return d
        layers = [layer(part) for part in original]
        for part in leaves(original):
            if radius := part.get('backgroundBlur'):
                # Tinting and Gaussian convolution commute; bake the backdrop once into its existing masks.
                for job in jobs:
                    if job['id'].startswith('cardy.' + variant['variant'] + '.') and job['id'] != part['id']:
                        job.setdefault('blurRegions', []).append({'bounds': part['bounds'], 'radius': radius / 2})
        bank_width = .54
        for part in original:
            x,y,w,h = part['bounds']
            if part['name'] == 'Right Side' and .4 < x < .65 and h > .9:
                bank_width = min(bank_width, x - .10)
        designs['cardy.' + variant['variant']] = {'layers': layers, 'bankWidth': bank_width}
        print(variant['variant'] + ': ' + '; '.join(f'{p["name"]} → {p["id"]}' for p in original[1:]), flush=True)

    node = r'''
import {astraSVG, astraStyles} from './docs/design/cardy/review/src/astra.js';
const p={background:'#010101',primary:'#020202',secondary:'#030303',accent:'#040404',highlight:'#050505'};
process.stdout.write(JSON.stringify(astraStyles.map(([id])=>({id:'astra.'+id,svg:astraSVG(id,p)
 .replace(/<defs><clipPath id="art">.*?<\/defs><g clip-path="url\(#art\)">/,'<g>')}))));
'''
    for part in json.loads(subprocess.check_output(['node', '--input-type=module', '-e', node], cwd=ROOT)):
        roles = {f'#{i:02X}{i:02X}{i:02X}': role for i, role in enumerate(ROLES, 1)}
        d = {'asset': part['id'], 'kind': 'vector', 'bounds': [0,0,1,1], 'blend': 'normal', 'opacity': 1,
             'roles': roles, 'toneMapped': False, 'masks': {}, 'category': 'pattern'}
        job = {'id': part['id'], 'masks': {}, 'neutral': None, 'mode': 'vector', 'vectors': {}, 'opacity': 1}
        for paint in roles:
            key = hashlib.sha256((part['id']+paint).encode()).hexdigest()[:16]
            path = CACHE / (key + '.svg'); path.write_text(role_svg(part['svg'], paint, [0,0,1,1]))
            job['vectors'][paint] = str(path); job['masks'][paint] = str(path.with_suffix('.png'))
        jobs.append(job); designs[part['id']] = {'layers': [d], 'bankWidth': .54}

    assert len(designs) == 37 and len({j['id'] for j in jobs}) == len(jobs)
    config = {'jobs': jobs, 'designs': designs}
    config_path = CACHE / 'fixed-jobs.json'; config_path.write_text(json.dumps(config))
    binary = CACHE / 'sample-card-parts'
    subprocess.run(['xcrun', 'swiftc', '-O', str(ROOT / 'scripts/sample-card-parts.swift'), '-o', str(binary)], check=True)
    subprocess.run([str(binary), str(config_path)], check=True, cwd=ROOT)
    nonempty = set(json.loads((CACHE / "nonempty-paints.json").read_text()))
    assets = {}
    for job in jobs:
        entry = {'masks': {}}
        for paint, filename in list(job['masks'].items()) + [(None, job['neutral'])]:
            if not filename or filename not in nonempty: continue
            data = Path(filename).read_bytes()
            name = 'cardpart-' + hashlib.sha256(data).hexdigest()[:16]
            folder = OUTPUT / (name + '.imageset'); folder.mkdir(exist_ok=True)
            (folder/'part.png').write_bytes(data)
            (folder/'Contents.json').write_text(json.dumps({'images':[{'filename':'part.png','idiom':'universal'}],
                'info':{'author':'xcode','version':1}},indent=2)+'\n')
            if paint is None: entry['neutral'] = name
            else: entry['masks'][paint] = name
        assets[job['id']] = entry
    for design in designs.values():
        for part in leaves(design['layers']): part.update(assets[part['asset']])
    used = {name for entry in assets.values() for name in list(entry['masks'].values()) + ([entry['neutral']] if 'neutral' in entry else [])}
    for folder in OUTPUT.glob('*.imageset'):
        if folder.stem not in used: shutil.rmtree(folder)
    (RESOURCES/'CardFaceDesigns.json').write_text(json.dumps(designs,sort_keys=True,separators=(',',':'))+'\n')
    assert all((OUTPUT/(name+'.imageset')/'part.png').stat().st_size for name in used)
    print(f'Generated {len(designs)} fixed designs, {len(jobs)} paint layers, {len(used)} unique masks/images; '
          f'{sum(p.stat().st_size for p in OUTPUT.rglob("*") if p.is_file())} asset bytes.')


if __name__ == '__main__':
    main()
