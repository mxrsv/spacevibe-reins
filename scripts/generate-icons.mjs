#!/usr/bin/env node
// Writes the app's icons as SwiftUI path code into Sources/SpaceVibe/Components, from three icon sets in their Iconify JSON form.
// No SVG is shipped or parsed at run time (spec docs/specs/2026-11-03-reins-design-language.md, v3 "Icons"; v5 spec V5-R9,
// V5-R10, V5-R12).
//
//   SpaceVibeIconData.swift     Solar Bold Duotone (480 Design, CC BY 4.0): the old screens, until the cut-over deletes them
//   CategoryIconData.swift  MingCute Line (MingCute Design, Apache-2.0): the category glyphs
//   ContentIconData.swift   Phosphor Duotone (Phosphor Icons, MIT): the v5 sidebar and content glyphs
//
//   cd <scratch folder outside the repo; never commit it>
//   npm pack @iconify-json/solar@1.2.13 @iconify-json/mingcute@1.2.10 @iconify-json/ph@1.2.2
//   for f in *.tgz; do mkdir "${f%.tgz}" && tar xzf "$f" -C "${f%.tgz}"; done
//   node scripts/generate-icons.mjs <solar>/package/icons.json <mingcute>/package/icons.json <ph>/package/icons.json
//
// Each glyph becomes one or two layers in its 24 x 24 box (Phosphor is scaled down from its 256 grid): the solid layer and,
// for the duotone sets, the lighter one. Both take one colour in the app. Every path is reduced to absolute move, line, cubic
// and close: H and V become lines, Q, T and S become cubics, and arcs are split into cubics of at most 90 degrees. Numbers
// are rounded to 3 decimals, glyphs are sorted by name, so a rerun on the same input writes the same files. Each file's header
// names the package version it was made from, and the licence notices live in Credits.swift (V5-R15).
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const OUT_DIR = join(REPO, 'Sources/SpaceVibe/Components');

/** [Swift case, Solar icon without the "-bold-duotone" suffix, what it stands for (the SF Symbol it replaces)]. The old screens. */
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
  ['globe', 'global', 'Settings: the interface language'],
  ['hook', 'lightning', 'a hook (bolt)'],
  ['info', 'info-circle', 'a note, a mixed cell (info.circle)'],
  ['limits', 'speedometer-max', 'Limits (gauge.with.dots.needle.33percent)'],
  ['loadout', 'layers', 'the Loadout tab (square.stack.3d.up)'],
  ['lock', 'lock', 'owned by a plugin, read-only (lock)'],
  ['monitor', 'monitor', 'Settings: the System theme, which follows macOS'],
  ['moon', 'moon', 'switch to the dark theme (moon)'],
  ['navigate', 'sort-vertical', 'the up and down keys in the palette footer (arrow.up.arrow.down)'],
  ['palette', 'pallete-2', 'Settings: the Appearance section and its Theme card'],
  ['refresh', 'refresh', 'read again, reading (arrow.clockwise, arrow.triangle.2.circlepath)'],
  ['rules', 'shield-check', 'the Rules tab (checkmark.shield)'],
  ['scriptMissing', 'folder-error', 'a hook script that is not there (questionmark.folder)'],
  ['search', 'magnifer', 'the search field (magnifyingglass)'],
  ['settings', 'settings', 'open Settings (gearshape)'],
  ['skill', 'stars-minimalistic', 'a skill (sparkles)'],
  ['stop', 'stop', 'stop a session (stop)'],
  ['sun', 'sun', 'switch to the light theme (sun.max)'],
  ['swap', 'transfer-horizontal', 'move a rule to another verdict (arrow.left.arrow.right)'],
  ['text', 'text', 'Settings: Font size'],
  ['tokens', 'chart-2', 'the Tokens tab, when it ships'],
  ['trash', 'trash-bin-minimalistic', 'remove (trash)'],
  ['undo', 'undo-left', 'Undo (arrow.uturn.backward)'],
  ['update', 'refresh-circle', 'Settings: the Update section'],
  ['warning', 'danger-triangle', 'a warning, not measurable (exclamationmark.triangle)'],
];

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

// MARK: Sources

/** [Swift case, MingCute icon without the "-line" suffix, what it stands for]. The category glyphs (spec V5-R10, D32). */
const CATEGORY_GLYPHS = [
  ['hook', 'fish-symbol', 'a hook (Hooks category)'],
  ['skill', 'flash', 'a skill (Skills category)'],
  ['subagent', 'robot', 'a subagent (Subagents category)'],
];

/** [Swift case, Phosphor icon without the "-duotone" suffix, what it stands for]. The mock's sidebar and content glyphs
 *  (system/shared.js sprite), plus the stop, copy and bug glyphs Activity drew page-locally. */
const CONTENT_GLYPHS = [
  ['bug', 'bug', 'a failed command (Activity: Failed tab); the mock draws its own bug, this is Phosphor\'s nearest'],
  ['caretDown', 'caret-down', 'a disclosure or menu chevron'],
  ['check', 'check', 'done, chosen'],
  ['clock', 'clock', 'a time, a stale or unknown reading, a newly added item'],
  ['close', 'x', 'dismiss, clear, remove a filter chip'],
  ['copy', 'copy', 'copy'],
  ['enter', 'arrow-elbow-down-left', 'Return, and refresh in the mock'],
  ['file', 'file', 'a file (Activity: Files tab, file rows)'],
  ['filter', 'funnel', 'the Filter button and its menu'],
  ['gauge', 'gauge', 'Limits (sidebar)'],
  ['lock', 'lock', 'owned by a plugin, read-only; Codex read-only'],
  ['moon', 'moon', 'switch to the dark appearance'],
  ['open', 'arrow-square-out', 'open a file or a session'],
  ['plus', 'plus', 'add'],
  ['pulse', 'pulse', 'Activity (sidebar, Running tab)'],
  ['rank', 'chart-bar', 'the Rank field of the filter menu; the mock draws three bars, this is Phosphor\'s nearest'],
  ['rule', 'list-checks', 'Rules category glyph (the mock\'s checklist; D32 names none)'],
  ['search', 'magnifying-glass', 'search (sidebar, fields)'],
  ['sliders', 'sliders-horizontal', 'Settings (sidebar), the View button'],
  ['stack', 'stack', 'Agents (sidebar), the CLI filter group'],
  ['stop', 'stop-circle', 'stop a session; the mock fills a rounded square, this is Phosphor\'s outlined one'],
  ['sun', 'sun', 'switch to the light appearance'],
  ['terminal', 'terminal-window', 'a CLI (the CLI field of the filter menu)'],
  ['trash', 'trash', 'remove'],
  ['warning', 'warning', 'a warning (never ran, can\'t run)'],
];

/**
 * One icon set and the Swift enum it becomes. `sourceOpacity` is the opacity the set gives its light layer, `layerOpacity`
 * the one the app draws it at; `outline` is the stroke the mock adds to a glyph (system/shared.css `.ico`, in the set's own
 * box units), reproduced so the app's glyphs weigh the same.
 */
const SOURCES = [
  {
    key: 'solar', label: 'Solar', prefix: 'solar', pkg: '@iconify-json/solar', license: 'CC-BY-4.0', box: 24, suffix: '-bold-duotone',
    glyphs: GLYPHS, out: 'SpaceVibeIconData.swift', type: 'SpaceVibeGlyph', light: true, sourceOpacity: 0.5, layerOpacity: 0.5, outline: 0,
    credit: 'Solar by 480 Design, CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/).',
    doc: ['Every icon the old screens draw, from Solar Bold Duotone. Each has a solid layer and a lighter one in a 24 x 24 box (`SpaceVibeIcon`',
      'draws them in one colour, the lighter at `layerOpacity`). The v5 screens use `CategoryGlyph` and `ContentGlyph` instead.'],
  },
  {
    key: 'mingcute', label: 'MingCute', prefix: 'mingcute', pkg: '@iconify-json/mingcute', license: 'Apache-2.0', box: 24, suffix: '-line',
    glyphs: CATEGORY_GLYPHS, out: 'CategoryIconData.swift', type: 'CategoryGlyph', light: false, sourceOpacity: 1, layerOpacity: 1, outline: 0,
    credit: 'MingCute by MingCute Design, Apache-2.0 (https://www.apache.org/licenses/LICENSE-2.0).\n// Changed from the original: the SVG path data is rewritten as absolute move, line and cubic commands (Apache-2.0 section 4(b)).',
    doc: ['The category glyphs (spec V5-R10), from MingCute Line: one layer in a 24 x 24 box, drawn in one colour.'],
  },
  {
    key: 'phosphor', label: 'Phosphor', prefix: 'ph', pkg: '@iconify-json/ph', license: 'MIT', box: 256, suffix: '-duotone',
    glyphs: CONTENT_GLYPHS, out: 'ContentIconData.swift', type: 'ContentGlyph', light: true, sourceOpacity: 0.2, layerOpacity: 0.25, outline: 8,
    credit: 'Phosphor Icons, Copyright (c) 2023 Phosphor Icons, MIT (https://github.com/phosphor-icons/core/blob/main/LICENSE).\n// Changed from the original: the SVG path data is rewritten as absolute move, line and cubic commands and scaled from the 256 grid to 24.',
    doc: ['The sidebar and content glyphs, from Phosphor Duotone, scaled from its 256 grid to a 24 x 24 box. Each has a solid layer and a lighter',
      'one (`SpaceVibeIcon` draws them in one colour, the lighter at `layerOpacity`, both with the kit\'s thin outline `outlineWidth`).'],
  },
];

// MARK: Glyphs

const DRAW_BOX = 24;

/** Scales path commands from the set's own box to the 24 box the app draws in. */
function scaled(commands, k) {
  return commands.map(([op, ...args]) => [op, ...args.map((v) => v * k)]);
}

/** The layers of one icon: commands and fill rule each. Throws on anything the source's layers cannot hold. */
export function glyphLayers(set, name, source) {
  const icon = set.icons[name];
  if (!icon) throw new Error(`${name}: not in the set`);
  if ((icon.width ?? set.width ?? DRAW_BOX) !== source.box || (icon.height ?? set.height ?? DRAW_BOX) !== source.box) {
    throw new Error(`${name}: not a ${source.box} box`);
  }
  if (icon.left || icon.top || icon.rotate || icon.hFlip || icon.vFlip) throw new Error(`${name}: transformed`);
  const k = DRAW_BOX / source.box;
  const layers = { solid: { commands: [], evenOdd: null }, light: { commands: [], evenOdd: null } };
  for (const element of elements(icon.body)) {
    const key = Math.abs(element.opacity - 1) < 1e-9 ? 'solid' : source.light && Math.abs(element.opacity - source.sourceOpacity) < 1e-9 ? 'light' : null;
    if (!key) throw new Error(`${name}: opacity ${element.opacity}`);
    const layer = layers[key];
    layer.commands.push(...scaled(element.commands, k));
    // One fill rule per layer. A layer that mixes them takes even-odd, which matches as long as its non-zero parts do not
    // overlap anything; check the result against the source (the plan's verification renders both).
    layer.evenOdd = (layer.evenOdd ?? false) || element.evenOdd;
  }
  for (const [key, layer] of Object.entries(layers)) {
    if (key === 'light' && !source.light) {
      if (layer.commands.length) throw new Error(`${name}: a light layer in a single-layer set`);
    } else if (!layer.commands.length) throw new Error(`${name}: no ${key} layer`);
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

export function swiftSource(source, set, version) {
  const glyphs = [...source.glyphs].sort((a, b) => a[0].localeCompare(b[0], 'en'));
  const built = glyphs.map(([name, icon, meaning]) => ({ name, icon: icon + source.suffix, meaning, layers: glyphLayers(set, icon + source.suffix, source) }));
  const cap = (s) => s[0].toUpperCase() + s.slice(1);
  const layerKeys = source.light ? ['solid', 'light'] : ['solid'];
  const out = [];
  out.push(`// Generated by scripts/generate-icons.mjs from ${source.pkg} ${version}. Do not edit; rerun the script.`);
  out.push(`// ${source.credit}`);
  out.push('import CoreGraphics');
  out.push('');
  for (const line of source.doc) out.push(`/// ${line}`);
  out.push(`enum ${source.type}: CaseIterable, GlyphSource {`);
  for (const g of built) out.push(`    /// ${cap(g.meaning)}.`, `    case ${g.name}`);
  out.push('', `    /// The ${source.label} icon the glyph is drawn from.`);
  out.push('    var iconName: String {', '        switch self {');
  for (const g of built) out.push(`        case .${g.name}: "${g.icon}"`);
  out.push('        }', '    }', '');
  out.push(`    var hasLightLayer: Bool { ${source.light} }`);
  out.push(`    var layerOpacity: Double { ${source.layerOpacity} }`);
  out.push(`    var outlineWidth: CGFloat { ${num(source.outline * DRAW_BOX / source.box)} }`, '');
  out.push('    /// Whether a layer fills even-odd, where the source cuts a hole.');
  out.push('    func evenOdd(_ layer: GlyphLayer) -> Bool {', '        switch layer {');
  for (const key of ['solid', 'light']) {
    const names = built.filter((g) => g.layers[key].evenOdd).map((g) => `.${g.name}`);
    out.push(`        case .${key}: ${names.length ? `[${names.join(', ')}].contains(self)` : 'false'}`);
  }
  out.push('        }', '    }', '');
  out.push('    func draw(_ layer: GlyphLayer, into p: inout GlyphPen) {', '        switch (self, layer) {');
  for (const g of built) for (const key of layerKeys) out.push(`        case (.${g.name}, .${key}): Self.${g.name}${cap(key)}(&p)`);
  if (!source.light) out.push('        case (_, .light): break');
  out.push('        }', '    }');
  for (const g of built) {
    for (const key of layerKeys) {
      out.push('', `    private static func ${g.name}${cap(key)}(_ p: inout GlyphPen) {`);
      for (const line of swiftLines(g.layers[key].commands)) out.push(`        ${line}`);
      out.push('    }');
    }
  }
  out.push('}', '');
  return out.join('\n');
}

function main() {
  const paths = process.argv.slice(2);
  if (paths.length !== SOURCES.length) {
    console.error('usage: node scripts/generate-icons.mjs <solar icons.json> <mingcute icons.json> <phosphor (ph) icons.json>');
    process.exit(2);
  }
  const outputs = SOURCES.map((source, i) => {
    const set = JSON.parse(readFileSync(paths[i], 'utf8'));
    const pkg = JSON.parse(readFileSync(join(dirname(paths[i]), 'package.json'), 'utf8'));
    if (set.prefix !== source.prefix || pkg.name !== source.pkg) throw new Error(`argument ${i + 1} is not ${source.pkg}`);
    if (pkg.license !== source.license) throw new Error(`${source.pkg}: licence changed to ${pkg.license}; check it before shipping`);
    return [join(OUT_DIR, source.out), swiftSource(source, set, pkg.version)];
  });
  // Nothing is written until every set has been read and checked.
  for (const [file, text] of outputs) {
    writeFileSync(file, text);
    console.log(file);
  }
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) main();
