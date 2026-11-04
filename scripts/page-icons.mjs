// The page icons: Tabler Icons outline (MIT, Paweł Kuna) as SwiftUI path code in
// Sources/Reins/Components/PageIconData.swift. Spec docs/specs/2026-11-03-reins-design-language.md, "v4 changes": the
// sidebar keeps Solar (scripts/generate-icons.mjs), everything inside a page draws these. Called by generate-icons.mjs
// when it is given the Tabler set:
//
//   npm pack @iconify-json/tabler       # into a scratch folder outside the repo; never commit it
//   tar xzf iconify-json-tabler-*.tgz
//   node scripts/generate-icons.mjs <scratch>/package/icons.json
//
// Tabler glyphs are stroked, not filled: every element must be a path with no fill, a 2 wide `currentColor` stroke and
// round caps and joins. The generator keeps the centre lines; `PageIcon` strokes them at 2 x size / 24 with round caps
// and joins. A glyph is one path in its 24 x 24 box. Numbers are rounded to 3 decimals and glyphs sorted by name, so a
// rerun on the same input writes the same file.
import { pathCommands, swiftLines } from './icon-paths.mjs';

/** [Swift case, Tabler icon, what it stands for]. The mock's names (mocks/agents/agents-panel-page-icons.js) map 1:1. */
export const PAGE_GLYPHS = [
  ['activity', 'activity', 'the Activity tab in the palette'],
  ['add', 'plus', 'add'],
  ['advanced', 'code', 'an agent\'s Advanced panel: the whole settings file'],
  ['agent', 'robot', 'a subagent'],
  ['arrowRight', 'arrow-right', 'go to a scope or an item'],
  ['back', 'chevron-left', 'back: Settings, a crumb'],
  ['check', 'check', 'done, chosen'],
  ['chevronDown', 'chevron-down', 'an open disclosure, a menu'],
  ['chevronRight', 'chevron-right', 'a closed disclosure, a link to more'],
  ['clock', 'clock', 'a time, a reading that is old'],
  ['close', 'x', 'dismiss, clear, close a panel'],
  ['copy', 'copy', 'copy'],
  ['download', 'download', 'see an update'],
  ['edit', 'pencil', 'edit a file'],
  ['enter', 'corner-down-left', 'the Return key in the palette footer'],
  ['error', 'circle-x', 'an error'],
  ['external', 'external-link', 'open in another app'],
  ['file', 'file-text', 'a file, an instruction file (the Rules panel)'],
  ['folder', 'folder', 'a folder, Show in Finder'],
  ['globe', 'world', 'Settings: the interface language'],
  ['hook', 'bolt', 'a hook'],
  ['info', 'info-circle', 'a note, a mixed cell'],
  ['key', 'key', 'a secret: an MCP server\'s environment or headers'],
  ['limits', 'gauge', 'Limits'],
  ['link', 'link', 'an imported file (`@path`)'],
  ['loadout', 'stack-2', 'the Loadout tab in the palette'],
  ['lock', 'lock', 'owned by a plugin, read-only'],
  ['mcp', 'plug', 'an MCP server'],
  ['model', 'cpu', 'a model'],
  ['monitor', 'device-desktop', 'Settings: the System theme, which follows macOS'],
  ['moon', 'moon', 'the dark theme'],
  ['navigate', 'arrows-up-down', 'the up and down keys in the palette footer'],
  ['palette', 'palette', 'Settings: the Appearance section and its Theme card'],
  ['permissions', 'shield-check', 'permissions: the Rules tab, an agent\'s Permissions panel'],
  ['preview', 'eye', 'preview a Markdown file'],
  ['refresh', 'refresh', 'read again, reading'],
  ['scriptMissing', 'file-alert', 'a hook script that is not there'],
  ['search', 'search', 'the search field'],
  ['selector', 'selector', 'a menu that picks one of several (scope, mode)'],
  ['settings', 'settings', 'Settings'],
  ['skill', 'sparkles', 'a skill'],
  ['stop', 'player-stop', 'stop a session'],
  ['sun', 'sun', 'the light theme'],
  ['swap', 'arrows-exchange', 'move a rule to another verdict'],
  ['text', 'typography', 'Settings: Font size'],
  ['tokens', 'chart-bar', 'the Tokens tab, when it ships'],
  ['trash', 'trash', 'remove'],
  ['undo', 'arrow-back-up', 'Undo'],
  ['update', 'refresh-dot', 'Settings: the Update section'],
  ['warning', 'alert-triangle', 'a warning, not measurable'],
];

const BOX = 24;
const STROKE = 2;
const STROKE_ATTRIBUTES = { fill: 'none', stroke: 'currentColor', 'stroke-linecap': 'round', 'stroke-linejoin': 'round', 'stroke-width': String(STROKE) };

/** Every path of an outline body as move, line, cubic and close. Refuses a fill, another stroke or any other element. */
export function strokeCommands(body, name) {
  const out = [];
  const stack = [{}];
  const tag = /<(\/?)([a-zA-Z]+)((?:\s+[a-zA-Z:-]+="[^"]*")*)\s*(\/?)>/g;
  let index = 0;
  for (let match = tag.exec(body); match; match = tag.exec(body)) {
    if (body.slice(index, match.index).trim()) throw new Error(`${name}: text between tags at ${index}`);
    index = tag.lastIndex;
    const [, closing, element, rawAttrs, selfClosing] = match;
    if (closing) {
      if (element !== 'g' || stack.length === 1) throw new Error(`${name}: unexpected </${element}>`);
      stack.pop();
      continue;
    }
    const attrs = Object.fromEntries([...rawAttrs.matchAll(/([a-zA-Z:-]+)="([^"]*)"/g)].map((m) => [m[1], m[2]]));
    const state = { ...stack[stack.length - 1] };
    for (const [key, value] of Object.entries(attrs)) {
      if (key === 'd') continue;
      if (!(key in STROKE_ATTRIBUTES)) throw new Error(`${name}: attribute ${key} on <${element}> is not drawn`);
      state[key] = value;
    }
    if (element === 'g') {
      if (!selfClosing) stack.push(state);
      continue;
    }
    if (element !== 'path' || !selfClosing || !attrs.d) throw new Error(`${name}: <${element}> is not a stroked path`);
    for (const [key, value] of Object.entries(STROKE_ATTRIBUTES)) {
      if (state[key] !== value) throw new Error(`${name}: ${key} is ${state[key]}, not ${value}`);
    }
    out.push(...pathCommands(attrs.d));
  }
  if (body.slice(index).trim() || stack.length !== 1) throw new Error(`${name}: unbalanced body`);
  if (!out.length) throw new Error(`${name}: no path`);
  return out;
}

export function pageSwiftSource(set, version) {
  const glyphs = [...PAGE_GLYPHS].sort((a, b) => a[0].localeCompare(b[0], 'en'));
  const built = glyphs.map(([name, tabler, meaning]) => {
    const icon = set.icons[tabler];
    if (!icon) throw new Error(`${tabler}: not in the set`);
    if ((icon.width ?? set.width ?? BOX) !== BOX || (icon.height ?? set.height ?? BOX) !== BOX) throw new Error(`${tabler}: not a 24 box`);
    if (icon.left || icon.top || icon.rotate || icon.hFlip || icon.vFlip) throw new Error(`${tabler}: transformed`);
    return { name, tabler, meaning, commands: strokeCommands(icon.body, tabler) };
  });
  const cap = (s) => s[0].toUpperCase() + s.slice(1);
  const out = [];
  out.push(`// Generated by scripts/generate-icons.mjs from @iconify-json/tabler ${version}. Do not edit; rerun the script.`);
  out.push('// Tabler Icons by Paweł Kuna, MIT (https://github.com/tabler/tabler-icons/blob/master/LICENSE).');
  out.push('import CoreGraphics');
  out.push('');
  out.push('/// Every icon a page draws, from Tabler Icons outline: one stroked path in a 24 x 24 box, drawn by `PageIcon` with a');
  out.push('/// `stroke` wide line and round caps and joins. The sidebar draws `ReinsGlyph` (Solar) instead.');
  out.push('enum PageGlyph: CaseIterable {');
  for (const g of built) out.push(`    /// ${cap(g.meaning)}.`, `    case ${g.name}`);
  out.push('', `    static let box: CGFloat = ${BOX}`, `    static let stroke: CGFloat = ${STROKE}`, '');
  out.push('    /// The Tabler icon the glyph is drawn from.');
  out.push('    var tablerName: String {', '        switch self {');
  for (const g of built) out.push(`        case .${g.name}: "${g.tabler}"`);
  out.push('        }', '    }', '');
  out.push('    /// The centre lines, in the 24 x 24 box.');
  out.push('    func draw(into p: inout GlyphPen) {', '        switch self {');
  for (const g of built) out.push(`        case .${g.name}: ${swiftLines(g.commands).join('; ')}`);
  out.push('        }', '    }', '}', '');
  return out.join('\n');
}
