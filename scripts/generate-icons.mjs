#!/usr/bin/env node
// Writes the app's icons as SwiftUI path code from an Iconify JSON set. No SVG is shipped or parsed at run time (spec
// docs/specs/2026-11-03-reins-design-language.md, v3 "Icons" and v4 "Two icon sets, split by job"). Two sources, picked by
// the set it is given:
//
//   Solar Bold Duotone (480 Design, CC BY 4.0) -> Sources/Reins/Components/ReinsIconData.swift, the sidebar's icons.
//   Tabler Icons outline (MIT) -> Sources/Reins/Components/PageIconData.swift, every icon inside a page (page-icons.mjs).
//
//   npm pack @iconify-json/solar        # or @iconify-json/tabler; into a scratch folder outside the repo, never commit it
//   tar xzf iconify-json-solar-*.tgz
//   node scripts/generate-icons.mjs <scratch>/package/icons.json
//
// Each Solar glyph becomes two layers in its 24 x 24 box: the solid layer and the lighter one Solar draws at 50% opacity.
// Both take one colour in the app. Every path is reduced to absolute move, line, cubic and close (icon-paths.mjs). Numbers
// are rounded to 3 decimals, glyphs are sorted by name, so a rerun on the same input writes the same file.
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { pathCommands, swiftLines } from './icon-paths.mjs';
import { pageSwiftSource } from './page-icons.mjs';

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const OUT = join(REPO, 'Sources/Reins/Components/ReinsIconData.swift');
const PAGE_OUT = join(REPO, 'Sources/Reins/Components/PageIconData.swift');

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
    console.error('usage: node scripts/generate-icons.mjs <path to @iconify-json/solar or @iconify-json/tabler icons.json>');
    process.exit(2);
  }
  const set = JSON.parse(readFileSync(source, 'utf8'));
  const pkg = JSON.parse(readFileSync(join(dirname(source), 'package.json'), 'utf8'));
  if (set.prefix === 'tabler' && pkg.name === '@iconify-json/tabler') {
    if (pkg.license !== 'MIT') throw new Error(`licence changed to ${pkg.license}: check it before shipping`);
    writeFileSync(PAGE_OUT, pageSwiftSource(set, pkg.version));
    console.log(PAGE_OUT);
    return;
  }
  if (set.prefix !== 'solar' || pkg.name !== '@iconify-json/solar') throw new Error('neither the Solar nor the Tabler set');
  if (pkg.license !== 'CC-BY-4.0') throw new Error(`licence changed to ${pkg.license}: check it before shipping`);
  writeFileSync(OUT, swiftSource(set, pkg.version));
  console.log(OUT);
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) main();
