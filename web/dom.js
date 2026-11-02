// All installed text reaches the DOM through textContent; nothing is parsed as HTML.
export function h(tag, props = {}, ...children) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(props)) {
    if (v == null || v === false) continue;
    if (k === 'class') el.className = v;
    else if (k === 'value') el.value = v;
    else if (k === 'checked') el.checked = !!v;
    else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
    else el.setAttribute(k, v === true ? '' : v);
  }
  el.append(...children.flat(Infinity).filter((c) => c != null && c !== false));
  return el;
}

const PATHS = {
  plus: 'M8 3v10M3 8h10',
  close: 'M3.5 3.5l9 9M12.5 3.5l-9 9',
  search: 'M7 12A5 5 0 1 0 7 2a5 5 0 0 0 0 10ZM10.7 10.7L14 14',
  skill: 'M3 2.5h7.5L13 5v8.5H3zM5.5 7h5M5.5 10h5',
  agent: 'M8 7.5a2.75 2.75 0 1 0 0-5.5 2.75 2.75 0 0 0 0 5.5ZM2.5 14a5.5 5.5 0 0 1 11 0',
  hook: 'M8 1.5v7.2a3 3 0 1 1-3-3M8 1.5L6 3.5M8 1.5l2 2',
  history: 'M2.5 8a5.5 5.5 0 1 0 1.7-4M2.5 2.5V5H5M8 5v3.3l2 1.2',
  copy: 'M5.5 5.5h8v8h-8zM10.5 5.5v-3h-8v8h3',
  trash: 'M3 4.5h10M6.5 4.5v-2h3v2M4.5 4.5l.7 9h5.6l.7-9',
  undo: 'M6 3L2.5 6.5 6 10M3 6.5h6.5a3.5 3.5 0 0 1 0 7H7',
};

export function icon(name) {
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('viewBox', '0 0 16 16');
  svg.setAttribute('aria-hidden', 'true');
  svg.setAttribute('class', 'icon');
  const p = document.createElementNS('http://www.w3.org/2000/svg', 'path');
  p.setAttribute('d', PATHS[name]);
  svg.append(p);
  return svg;
}

export const CLI_LABEL = { claude: 'Claude Code', codex: 'Codex' };
export const shortDate = (day) => (day ? new Date(`${day}T00:00:00`).toLocaleDateString('en-US', { month: 'short', day: 'numeric' }) : '—');
export const num = (n) => n.toLocaleString('en-US');
export const ms = (n) => (n == null ? '—' : n < 1000 ? `${n} ms` : n < 60000 ? `${(n / 1000).toFixed(1)} s` : n < 3600000 ? `${Math.round(n / 60000)} min` : `${(n / 3600000).toFixed(1)} h`);
