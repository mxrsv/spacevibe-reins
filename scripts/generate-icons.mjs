#!/usr/bin/env node
// Writes Sources/Reins/Components/ReinsIconData.swift: the app's icons as SwiftUI path code, from the Solar icon set
// (Solar by 480 Design, CC BY 4.0) in its Iconify JSON form. No SVG is shipped or parsed at run time (spec
// docs/specs/2026-11-03-reins-design-language.md, v3 "Icons"; plan task V4).
//
//   npm pack @iconify-json/solar        # into a scratch folder outside the repo; never commit it
//   tar xzf iconify-json-solar-*.tgz
//   node scripts/generate-icons.mjs <scratch>/package/icons.json
//
// Each glyph becomes two layers in its 24 x 24 box: the solid layer and the lighter one Solar draws at 50% opacity. Both
// take one colour in the app. Every path is reduced to absolute move, line, cubic and close: H and V become lines, Q, T
// and S become cubics, and arcs are split into cubics of at most 90 degrees. Numbers are rounded to 3 decimals, glyphs are
// sorted by name, so a rerun on the same input writes the same file.
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const OUT = join(REPO, 'Sources/Reins/Components/ReinsIconData.swift');

/** [Swift case, Solar icon without the "-bold-duotone" suffix, what it stands for (the SF Symbol it replaces)]. */
export const GLYPHS = [
  ['activity', 'pulse', 'the Activity tab (waveform.path.ecg)'],
  ['add', 'add', 'add (plus)'],
  ['agent', 'bot', 'an agent (person.crop.square)'],
  ['arrowRight', 'arrow-right', 'go to a scope or an item (arrow.right)'],
  ['check', 'check', 'done, chosen (checkmark)'],
  ['clock', 'clock-circle', 'a time, a reading that is old (clock)'],
  ['close', 'close', 'dismiss, clear (xmark)'],
  ['copy', 'copy', 'copy (doc.on.doc)'],
  ['download', 'round-arrow-down', 'see an update (arrow.down.circle)'],
  ['enter', 'undo-left-round', 'the Return key in the palette footer (return)'],
  ['error', 'danger-circle', 'an error (xmark.octagon)'],
  ['file', 'file-text', 'a file in the file history (doc)'],
  ['hook', 'lightning', 'a hook (bolt)'],
  ['info', 'info-circle', 'a note, a mixed cell (info.circle)'],
  ['limits', 'speedometer-max', 'Limits (gauge.with.dots.needle.33percent)'],
  ['loadout', 'layers', 'the Loadout tab (square.stack.3d.up)'],
  ['lock', 'lock', 'owned by a plugin, read-only (lock)'],
  ['moon', 'moon', 'switch to the dark theme (moon)'],
  ['navigate', 'sort-vertical', 'the up and down keys in the palette footer (arrow.up.arrow.down)'],
  ['refresh', 'refresh', 'read again, reading (arrow.clockwise, arrow.triangle.2.circlepath)'],
  ['rules', 'shield-check', 'the Rules tab (checkmark.shield)'],
  ['scriptMissing', 'folder-error', 'a hook script that is not there (questionmark.folder)'],
  ['search', 'magnifer', 'the search field (magnifyingglass)'],
  ['skill', 'stars-minimalistic', 'a skill (sparkles)'],
  ['stop', 'stop', 'stop a session (stop)'],
  ['sun', 'sun', 'switch to the light theme (sun.max)'],
  ['swap', 'transfer-horizontal', 'move a rule to another verdict (arrow.left.arrow.right)'],
  ['tokens', 'chart-2', 'the Tokens tab, when it ships'],
  ['trash', 'trash-bin-minimalistic', 'remove (trash)'],
  ['undo', 'undo-left', 'Undo (arrow.uturn.backward)'],
  ['warning', 'danger-triangle', 'a warning, not measurable (exclamationmark.triangle)'],
];

const SUFFIX = '-bold-duotone';
const BOX = 24;
const LIGHT_OPACITY = 0.5;

// MARK: SVG body

/** The filled elements of an icon body, each with its own opacity and fill rule. Refuses anything it does not draw. */
export function elements(body) {
  const out = [];
  const stack = [{ opacity: 1, evenOdd: false }];
  const tag = /<(\/?)([a-zA-Z]+)((?:\s+[a-zA-Z:-]+="[^"]*")*)\s*(\/?)>/g;
  let index = 0;
  for (let match = tag.exec(body); match; match = tag.exec(body)) {
    if (body.slice(index, match.index).trim()) throw new Error(`text between tags at ${index}`);
    index = tag.lastIndex;
    const [, closing, name, rawAttrs, selfClosing] = match;
    if (closing) {
      if (name !== 'g' || stack.length === 1) throw new Error(`unexpected </${name}>`);
      stack.pop();
      continue;
    }
    const attrs = Object.fromEntries([...rawAttrs.matchAll(/([a-zA-Z:-]+)="([^"]*)"/g)].map((m) => [m[1], m[2]]));
    for (const key of Object.keys(attrs)) {
      if (!['d', 'fill', 'opacity', 'fill-rule', 'clip-rule', 'cx', 'cy', 'r', 'rx', 'ry', 'x', 'y', 'width', 'height'].includes(key)) {
        throw new Error(`attribute ${key} on <${name}> is not drawn`);
      }
    }
    if (attrs.fill && attrs.fill !== 'currentColor') throw new Error(`fill ${attrs.fill}`);
    const parent = stack[stack.length - 1];
    const state = {
      opacity: parent.opacity * (attrs.opacity === undefined ? 1 : Number(attrs.opacity)),
      evenOdd: attrs['fill-rule'] === undefined ? parent.evenOdd : attrs['fill-rule'] === 'evenodd',
    };
    if (name === 'g') {
      if (!selfClosing) stack.push(state);
      continue;
    }
    if (!selfClosing) throw new Error(`<${name}> with children`);
    out.push({ ...state, commands: shapeCommands(name, attrs) });
  }
  if (body.slice(index).trim() || stack.length !== 1) throw new Error('unbalanced body');
  return out;
}

function shapeCommands(name, a) {
  const n = (key, fallback) => (a[key] === undefined ? fallback : Number(a[key]));
  switch (name) {
    case 'path':
      return pathCommands(a.d);
    case 'circle':
      return ellipseCommands(n('cx', 0), n('cy', 0), n('r'), n('r'));
    case 'ellipse':
      return ellipseCommands(n('cx', 0), n('cy', 0), n('rx'), n('ry'));
    case 'rect': {
      const [x, y, w, h] = [n('x', 0), n('y', 0), n('width'), n('height')];
      const rx = Math.min(n('rx', n('ry', 0)), w / 2);
      const ry = Math.min(n('ry', n('rx', 0)), h / 2);
      if (!rx || !ry) return [['M', x, y], ['L', x + w, y], ['L', x + w, y + h], ['L', x, y + h], ['Z']];
      return pathCommands(`M${x + rx} ${y}H${x + w - rx}A${rx} ${ry} 0 0 1 ${x + w} ${y + ry}V${y + h - ry}A${rx} ${ry} 0 0 1 ${x + w - rx} ${y + h}H${x + rx}A${rx} ${ry} 0 0 1 ${x} ${y + h - ry}V${y + ry}A${rx} ${ry} 0 0 1 ${x + rx} ${y}Z`);
    }
    default:
      throw new Error(`<${name}> is not drawn`);
  }
}

function ellipseCommands(cx, cy, rx, ry) {
  return pathCommands(`M${cx - rx} ${cy}A${rx} ${ry} 0 1 0 ${cx + rx} ${cy}A${rx} ${ry} 0 1 0 ${cx - rx} ${cy}Z`);
}

// MARK: Path data

/** Tokens of path data: command letters and numbers, with packed forms ("1.5.5", "1-2", arc flags "01") split. */
function tokens(d) {
  const out = [];
  const re = /([MmLlHhVvCcSsQqTtAaZz])|([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)|([\s,]+)/y;
  let at = 0;
  while (at < d.length) {
    re.lastIndex = at;
    const match = re.exec(d);
    if (!match) throw new Error(`cannot read path data at ${at}: ${d.slice(at, at + 12)}`);
    if (match[1]) out.push(match[1]);
    else if (match[2]) out.push(match[2]);
    at = re.lastIndex;
  }
  return out;
}

const ARITY = { M: 2, L: 2, H: 1, V: 1, C: 6, S: 4, Q: 4, T: 2, A: 7, Z: 0 };

/** Absolute M, L, C and Z only. */
export function pathCommands(d) {
  const list = tokens(d);
  const out = [];
  let i = 0;
  let command = null;
  let x = 0, y = 0, startX = 0, startY = 0;
  let lastCubic = null, lastQuad = null;

  const number = () => {
    const value = list[i++];
    if (value === undefined || /[a-zA-Z]/.test(value)) throw new Error(`missing number for ${command}`);
    return Number(value);
  };
  // An arc flag may be packed against the next number: "a1 1 0 01.5 2" holds flags 0 and 1, then .5.
  const flag = () => {
    const value = list[i];
    if (value === '0' || value === '1') { i++; return Number(value); }
    if (/^[01]/.test(value)) { list[i] = value.slice(1); return Number(value[0]); }
    throw new Error(`bad arc flag ${value}`);
  };

  while (i < list.length) {
    if (/[a-zA-Z]/.test(list[i])) command = list[i++];
    else if (!command) throw new Error('path data starts with a number');
    const upper = command.toUpperCase();
    const relative = command !== upper;
    const ox = relative ? x : 0, oy = relative ? y : 0;
    let cubic = null, quad = null;
    switch (upper) {
      case 'M': {
        x = ox + number(); y = oy + number();
        startX = x; startY = y;
        out.push(['M', x, y]);
        command = relative ? 'l' : 'L'; // pairs after a move are lines
        break;
      }
      case 'L': x = ox + number(); y = oy + number(); out.push(['L', x, y]); break;
      case 'H': x = ox + number(); out.push(['L', x, y]); break;
      case 'V': y = oy + number(); out.push(['L', x, y]); break;
      case 'C': {
        const c = [ox + number(), oy + number(), ox + number(), oy + number(), ox + number(), oy + number()];
        out.push(['C', ...c]);
        cubic = [c[2], c[3]]; x = c[4]; y = c[5];
        break;
      }
      case 'S': {
        const [rx1, ry1] = lastCubic ? [2 * x - lastCubic[0], 2 * y - lastCubic[1]] : [x, y];
        const c = [ox + number(), oy + number(), ox + number(), oy + number()];
        out.push(['C', rx1, ry1, ...c]);
        cubic = [c[0], c[1]]; x = c[2]; y = c[3];
        break;
      }
      case 'Q': {
        const q = [ox + number(), oy + number(), ox + number(), oy + number()];
        out.push(quadToCubic(x, y, ...q));
        quad = [q[0], q[1]]; x = q[2]; y = q[3];
        break;
      }
      case 'T': {
        const [qx, qy] = lastQuad ? [2 * x - lastQuad[0], 2 * y - lastQuad[1]] : [x, y];
        const end = [ox + number(), oy + number()];
        out.push(quadToCubic(x, y, qx, qy, ...end));
        quad = [qx, qy]; [x, y] = end;
        break;
      }
      case 'A': {
        const rx = number(), ry = number(), rotation = number(), large = flag(), sweep = flag();
        const ex = ox + number(), ey = oy + number();
        out.push(...arcToCubics(x, y, rx, ry, rotation, large, sweep, ex, ey));
        x = ex; y = ey;
        break;
      }
      case 'Z':
        out.push(['Z']);
        x = startX; y = startY;
        break;
      default:
        throw new Error(`unknown command ${command}`);
    }
    lastCubic = cubic; lastQuad = quad;
    if (ARITY[upper] === 0 && i < list.length && !/[a-zA-Z]/.test(list[i])) throw new Error('number after Z');
  }
  return out;
}

function quadToCubic(x0, y0, qx, qy, x, y) {
  return ['C', x0 + (2 / 3) * (qx - x0), y0 + (2 / 3) * (qy - y0), x + (2 / 3) * (qx - x), y + (2 / 3) * (qy - y), x, y];
}

/** SVG arc (endpoint form) as cubics, per the SVG 1.1 implementation notes (F.6.5 and F.6.6). */
function arcToCubics(x1, y1, rxIn, ryIn, angle, large, sweep, x2, y2) {
  if (x1 === x2 && y1 === y2) return [];
  let rx = Math.abs(rxIn), ry = Math.abs(ryIn);
  if (!rx || !ry) return [['L', x2, y2]];
  const phi = (angle * Math.PI) / 180;
  const cos = Math.cos(phi), sin = Math.sin(phi);
  const dx = (x1 - x2) / 2, dy = (y1 - y2) / 2;
  const x1p = cos * dx + sin * dy, y1p = -sin * dx + cos * dy;
  const lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry);
  if (lambda > 1) { rx *= Math.sqrt(lambda); ry *= Math.sqrt(lambda); }
  const sign = large === sweep ? -1 : 1;
  const num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p;
  const den = rx * rx * y1p * y1p + ry * ry * x1p * x1p;
  const coef = sign * Math.sqrt(Math.max(0, num / den));
  const cxp = (coef * rx * y1p) / ry, cyp = (-coef * ry * x1p) / rx;
  const cx = cos * cxp - sin * cyp + (x1 + x2) / 2, cy = sin * cxp + cos * cyp + (y1 + y2) / 2;
  const vecAngle = (ux, uy, vx, vy) => Math.atan2(ux * vy - uy * vx, ux * vx + uy * vy);
  const theta1 = vecAngle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry);
  let delta = vecAngle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry);
  if (!sweep && delta > 0) delta -= 2 * Math.PI;
  if (sweep && delta < 0) delta += 2 * Math.PI;
  const segments = Math.max(1, Math.ceil(Math.abs(delta) / (Math.PI / 2) - 1e-9));
  const step = delta / segments;
  const k = (4 / 3) * Math.tan(step / 4);
  const point = (t) => [cx + rx * Math.cos(t) * cos - ry * Math.sin(t) * sin, cy + rx * Math.cos(t) * sin + ry * Math.sin(t) * cos];
  const tangent = (t) => [-rx * Math.sin(t) * cos - ry * Math.cos(t) * sin, -rx * Math.sin(t) * sin + ry * Math.cos(t) * cos];
  const out = [];
  for (let s = 0; s < segments; s++) {
    const t1 = theta1 + s * step, t2 = t1 + step;
    const [p1x, p1y] = point(t1), [p2x, p2y] = s === segments - 1 ? [x2, y2] : point(t2);
    const [d1x, d1y] = tangent(t1), [d2x, d2y] = tangent(t2);
    out.push(['C', p1x + k * d1x, p1y + k * d1y, p2x - k * d2x, p2y - k * d2y, p2x, p2y]);
  }
  return out;
}

// MARK: Glyphs

/** Both layers of one Solar icon: commands and fill rule each. Throws on anything the two layers cannot hold. */
export function glyphLayers(set, solarName) {
  const icon = set.icons[solarName];
  if (!icon) throw new Error(`${solarName}: not in the set`);
  if ((icon.width ?? set.width ?? BOX) !== BOX || (icon.height ?? set.height ?? BOX) !== BOX) throw new Error(`${solarName}: not a 24 box`);
  if (icon.left || icon.top || icon.rotate || icon.hFlip || icon.vFlip) throw new Error(`${solarName}: transformed`);
  const layers = { solid: { commands: [], evenOdd: null }, light: { commands: [], evenOdd: null } };
  for (const element of elements(icon.body)) {
    const key = Math.abs(element.opacity - 1) < 1e-9 ? 'solid' : Math.abs(element.opacity - LIGHT_OPACITY) < 1e-9 ? 'light' : null;
    if (!key) throw new Error(`${solarName}: opacity ${element.opacity}`);
    const layer = layers[key];
    layer.commands.push(...element.commands);
    // One fill rule per layer. A layer that mixes them takes even-odd, which matches as long as its non-zero parts do not
    // overlap anything; check the result against the source (the plan's verification renders both).
    layer.evenOdd = (layer.evenOdd ?? false) || element.evenOdd;
  }
  for (const [key, layer] of Object.entries(layers)) {
    if (!layer.commands.length) throw new Error(`${solarName}: no ${key} layer`);
    layer.evenOdd = Boolean(layer.evenOdd);
  }
  return layers;
}

// MARK: Swift

const num = (v) => {
  const s = String(Number(v.toFixed(3)));
  return s === '-0' ? '0' : s;
};

function swiftLines(commands) {
  const lines = [];
  let line = [];
  for (const [op, ...args] of commands) {
    if (op === 'M' && line.length) { lines.push(line.join('; ')); line = []; }
    line.push(`p.${op.toLowerCase()}(${args.map(num).join(', ')})`);
  }
  if (line.length) lines.push(line.join('; '));
  return lines;
}

export function swiftSource(set, version) {
  const glyphs = [...GLYPHS].sort((a, b) => a[0].localeCompare(b[0], 'en'));
  const built = glyphs.map(([name, solar, meaning]) => ({ name, solar: solar + SUFFIX, meaning, layers: glyphLayers(set, solar + SUFFIX) }));
  const cap = (s) => s[0].toUpperCase() + s.slice(1);
  const out = [];
  out.push(`// Generated by scripts/generate-icons.mjs from @iconify-json/solar ${version}. Do not edit; rerun the script.`);
  out.push('// Solar by 480 Design, CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/).');
  out.push('import CoreGraphics');
  out.push('');
  out.push('/// Every icon the app draws, from Solar Bold Duotone. Each has a solid layer and a lighter one in a 24 x 24 box (`ReinsIcon`');
  out.push('/// draws them in one colour, the lighter at `lightOpacity`).');
  out.push('enum ReinsGlyph: CaseIterable {');
  for (const g of built) out.push(`    /// ${cap(g.meaning)}.`, `    case ${g.name}`);
  out.push('', `    static let box: CGFloat = ${BOX}`, `    static let lightOpacity = ${LIGHT_OPACITY}`, '');
  out.push('    /// The Solar icon the glyph is drawn from.');
  out.push('    var solarName: String {', '        switch self {');
  for (const g of built) out.push(`        case .${g.name}: "${g.solar}"`);
  out.push('        }', '    }', '');
  out.push('    /// Whether a layer fills even-odd, where the source cuts a hole.');
  out.push('    func evenOdd(_ layer: GlyphLayer) -> Bool {', '        switch layer {');
  for (const key of ['solid', 'light']) {
    const names = built.filter((g) => g.layers[key].evenOdd).map((g) => `.${g.name}`);
    out.push(`        case .${key}: ${names.length ? `[${names.join(', ')}].contains(self)` : 'false'}`);
  }
  out.push('        }', '    }', '');
  out.push('    func draw(_ layer: GlyphLayer, into p: inout GlyphPen) {', '        switch (self, layer) {');
  for (const g of built) for (const key of ['solid', 'light']) out.push(`        case (.${g.name}, .${key}): Self.${g.name}${cap(key)}(&p)`);
  out.push('        }', '    }');
  for (const g of built) {
    for (const key of ['solid', 'light']) {
      out.push('', `    private static func ${g.name}${cap(key)}(_ p: inout GlyphPen) {`);
      for (const line of swiftLines(g.layers[key].commands)) out.push(`        ${line}`);
      out.push('    }');
    }
  }
  out.push('}', '');
  return out.join('\n');
}

function main() {
  const source = process.argv[2];
  if (!source) {
    console.error('usage: node scripts/generate-icons.mjs <path to @iconify-json/solar icons.json>');
    process.exit(2);
  }
  const set = JSON.parse(readFileSync(source, 'utf8'));
  const pkg = JSON.parse(readFileSync(join(dirname(source), 'package.json'), 'utf8'));
  if (set.prefix !== 'solar' || pkg.name !== '@iconify-json/solar') throw new Error('not the Solar set');
  if (pkg.license !== 'CC-BY-4.0') throw new Error(`licence changed to ${pkg.license}: check it before shipping`);
  writeFileSync(OUT, swiftSource(set, pkg.version));
  console.log(OUT);
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) main();
