'use strict';
/* C′ mock, plan task A0b: Codex permission profiles (`default_permissions` + `[permissions.<name>]`) and the state where
   both permission models are set. Schema from https://learn.chatgpt.com/docs/permissions.md (read 2026-11-05).
   Demo data: add `codex=profiles` or `codex=both` to the query or the hash. Loads after agents-panel-views.js. */

const BUILTIN = [
  { v: ':read-only', d: 'Reads files, writes nothing, no network.' },
  { v: ':workspace', d: 'Reads files, writes inside the workspace roots, no network.' },
  { v: ':danger-full-access', d: 'Reads and writes anywhere, with network.', warn: true },
];
const ACCESS = { read: { l: 'Read', tone: 'ok' }, write: { l: 'Write', tone: 'warn' }, deny: { l: 'Deny', tone: 'bad' } };
const DOMAIN_ACCESS = { allow: { l: 'Allow', tone: 'ok' }, deny: { l: 'Deny', tone: 'bad' } };
const asOptions = (map) => Object.entries(map).map(([v, o]) => ({ v, l: o.l, tone: o.tone }));

const DEMO_PROFILES = [
  {
    name: 'project-edit', extends: ':workspace',
    fs: [{ p: ':workspace_roots', a: 'write' }, { p: ':workspace_roots/**/*.env', a: 'deny' }, { p: '~/.ssh', a: 'deny' }, { p: ':tmpdir', a: 'write' }],
    net: { enabled: true, proxy: true, domains: [{ h: 'api.openai.com', a: 'allow' }, { h: '**.npmjs.org', a: 'allow' }, { h: '*.internal.example', a: 'deny' }] },
  },
  { name: 'review-only', extends: ':read-only', fs: [], net: { enabled: false, proxy: false, domains: [] } },
];
const CODEX_VARIANT = PARAMS.get('codex') || new URLSearchParams(location.hash.slice(1)).get('codex');
{
  const g = saved['codex/permissions/global'];
  if (CODEX_VARIANT === 'profiles') saved['codex/permissions/global'] = { ...g, model: 'profiles', sandbox: null, network: null, active: 'project-edit', profiles: clone(DEMO_PROFILES) };
  if (CODEX_VARIANT === 'both') saved['codex/permissions/global'] = { ...g, model: 'both', active: 'project-edit', profiles: clone(DEMO_PROFILES) };
}

const isBuiltin = (name) => name?.startsWith(':');
const profileOf = (d, name) => d.profiles?.find((p) => p.name === name);
function fsLabel(p) {
  const [root, ...rest] = p.split('/');
  const names = { ':workspace_roots': 'Workspace roots', ':tmpdir': 'Temp folder', ':slash_tmp': '/tmp', ':root': 'Whole disk', ':minimal': 'System basics' };
  if (!names[root]) return p;
  return rest.length ? `${names[root]} › ${rest.join('/')}` : names[root];
}
function fsKey(p) {
  const [root, ...rest] = p.split('/');
  return root.startsWith(':') ? `filesystem."${root}"${rest.length ? `."${rest.join('/')}"` : ''}` : `filesystem."${p}"`;
}

/* One plain sentence for the active profile, and whether it deserves the warn tone (no sandbox, or open network). */
function profileSummary(v) {
  if (isBuiltin(v.active)) {
    const b = BUILTIN.find((x) => x.v === v.active);
    return { text: { ':read-only': 'Reads only', ':workspace': 'Writes only inside the workspace roots', ':danger-full-access': 'Can write anywhere' }[v.active], warn: !!b?.warn };
  }
  const p = profileOf(v, v.active);
  if (!p) return { text: `Uses the profile ${v.active}`, warn: false };
  const writes = p.fs.filter((f) => f.a === 'write').map((f) => fsLabel(f.p).toLowerCase());
  const denies = p.fs.filter((f) => f.a === 'deny').length;
  const allow = p.net.domains.filter((x) => x.a === 'allow').length;
  const parts = [writes.length ? `Writes in ${writes.join(' and ')}` : 'Writes nothing'];
  if (denies) parts.push(`blocks ${plural(denies, 'path')}`);
  parts.push(!p.net.enabled ? 'no network' : p.net.proxy ? `network to ${plural(allow, 'domain')}` : 'open network');
  return { text: parts.join(', '), warn: p.net.enabled && !p.net.proxy };
}

function codexBothCard(d) {
  const option = (v, title, line) => `<button class="choice${d.model === v ? ' on' : ''}" data-act="keep-model" data-v="${v}" aria-pressed="${d.model === v}">
      <span class="row-title">${title}</span><span class="caption t3">${line}</span></button>`;
  return `<div class="card">${cardHead('Keep one permission model', { detail: 'Codex reads only one' })}
    <div class="choices">${option('legacy', 'Keep sandbox_mode', 'What Codex uses now. Removes <code>default_permissions</code>; the profiles stay in the file, unused.')}
    ${option('profiles', `Keep the profile ${esc(d.active)}`, 'Removes <code>sandbox_mode</code> and <code>[sandbox_workspace_write]</code>.')}</div></div>`;
}

function codexProfilesBody(d, approvalRow) {
  const active = isBuiltin(d.active) ? BUILTIN.find((b) => b.v === d.active) : null;
  const picker = `<div class="row stack static"><span class="grow"><span class="row-title">Permission profile</span><span class="code t3">default_permissions</span></span>
    <button class="scope${active?.warn ? ' warn' : ''}" style="width:100%" data-act="profile-menu" aria-haspopup="menu">${active?.warn ? icon('warning', 'i14') : ''}<span class="code-body">${esc(d.active)}</span>${icon('updown', 'i14')}</button>
    ${active ? `<span class="caption ${active.warn ? 'warn' : 't3'}">${esc(active.d)} Built-in profiles cannot be changed; pick a named one to edit.</span>` : ''}</div>`;
  const head = `<div class="card">${cardHead('How Codex runs', { detail: 'config.toml' })}${approvalRow}${picker}</div>`;
  const p = profileOf(d, d.active);
  if (!p) return head;
  const fsRows = p.fs.map((f) => `<div class="row"><span class="grow"><span class="row-title trunc" title="${esc(fsLabel(f.p))}">${esc(fsLabel(f.p))}</span><span class="code t3 trunc" title="${esc(fsKey(f.p))}">${esc(fsKey(f.p))}</span></span>
      ${seg('fs-access', asOptions(ACCESS), f.a, '', `data-prof="${esc(p.name)}" data-p="${esc(f.p)}"`)}<span class="acts"><button class="btn icon" data-act="rm-fs" data-p="${esc(f.p)}" aria-label="Remove ${esc(fsLabel(f.p))}">${icon('trash')}</button></span></div>`).join('');
  const domains = p.net.domains.map((x) => `<div class="row"><span class="grow"><span class="code-title trunc">${esc(x.h)}</span></span>
      ${seg('domain-access', asOptions(DOMAIN_ACCESS), x.a, '', `data-h="${esc(x.h)}"`)}<span class="acts"><button class="btn icon" data-act="rm-domain" data-h="${esc(x.h)}" aria-label="Remove ${esc(x.h)}">${icon('trash')}</button></span></div>`).join('');
  const parents = [':read-only', ':workspace', ...d.profiles.filter((x) => x.name !== p.name).map((x) => x.name)];
  return `${head}
    <div class="card">${cardHead(esc(p.name), { detail: `[permissions.${p.name}]` })}
      <div class="row static"><span class="grow"><span class="row-title">Based on</span><span class="code t3">extends</span></span><button class="scope" data-act="extends-menu" data-parents="${esc(parents.join(','))}" aria-haspopup="menu"><span class="code-body">${esc(p.extends)}</span>${icon('updown', 'i14')}</button></div>
      <div class="section-row"><span class="label t2">Files</span><span class="caption t3 num">${p.fs.length}</span></div>
      <div class="add-row two">${field('fs', '~/path, or a glob like **/*.pem')}${seg('new-access', asOptions(ACCESS), state.form.newAccess ?? 'read')}${addBtn('add-fs', 'fs')}</div>
      ${fsRows || '<div class="note caption">Only what the base profile allows.</div>'}
      <div class="section-row"><span class="label t2">Network</span></div>
      <div class="row static"><span class="grow"><span class="row-title">Network</span><span class="code t3">network.enabled</span></span><button class="switch" role="switch" aria-checked="${p.net.enabled}" aria-label="Network" data-act="net-enabled"></button></div>
      ${p.net.enabled ? `<div class="row static"><span class="grow"><span class="row-title">Enforce domain rules</span><span class="code t3">features.network_proxy</span></span><button class="switch" role="switch" aria-checked="${p.net.proxy}" aria-label="Enforce domain rules" data-act="net-proxy"></button></div>
      ${p.net.proxy ? '' : '<div class="note caption warn">Without it, the network is open to every domain.</div>'}
      <div class="add-row two">${field('domain', 'Host, *.example.com or **.example.com')}${seg('new-domain-access', asOptions(DOMAIN_ACCESS), state.form.newDomainAccess ?? 'allow')}${addBtn('add-domain', 'domain')}</div>
      ${domains || '<div class="note caption">No domain rules: every external destination is blocked.</div>'}` : ''}
    </div>`;
}

function profileChanges(a, b, out, listDiff) {
  if (a.model !== b.model) out.push({ op: 'Change', text: b.model === 'profiles' ? 'remove sandbox_mode and [sandbox_workspace_write]' : 'remove default_permissions' });
  if (a.active !== b.active) out.push({ op: 'Change', text: `default_permissions → "${b.active}"`, warn: b.active === ':danger-full-access' ? WARN.full : null });
  for (const p of b.profiles ?? []) {
    const q = profileOf(a, p.name);
    if (!q) continue;
    if (q.extends !== p.extends) out.push({ op: 'Change', text: `${p.name} extends → "${p.extends}"` });
    listDiff(q.fs, p.fs, (f) => f.p, (f) => f.a, (f) => ({ tag: ACCESS[f.a], text: `${p.name}: ${fsLabel(f.p)}` }));
    if (q.net.enabled !== p.net.enabled) out.push({ op: 'Change', text: `${p.name} network.enabled → ${p.net.enabled}` });
    if (q.net.proxy !== p.net.proxy) out.push({ op: 'Change', text: `features.network_proxy → ${p.net.proxy}`, warn: p.net.enabled && !p.net.proxy ? 'Codex will reach every domain: the domain rules stop applying.' : null });
    listDiff(q.net.domains, p.net.domains, (x) => x.h, (x) => x.a, (x) => ({ tag: DOMAIN_ACCESS[x.a], text: `${p.name}: ${x.h}` }));
  }
}

/* Edits to the active named profile in the draft. */
const editProfile = (fn) => edit((d) => { fn(profileOf(d, d.active), d); return d; });

const PROFILE_SEG = {
  'fs-access': (v, b) => editProfile((p) => { p.fs = p.fs.map((f) => (f.p === b.dataset.p ? { ...f, a: v } : f)); }),
  'domain-access': (v, b) => editProfile((p) => { p.net.domains = p.net.domains.map((x) => (x.h === b.dataset.h ? { ...x, a: v } : x)); }),
  'new-access': (v) => { state.form.newAccess = v; rerenderPanel(); },
  'new-domain-access': (v) => { state.form.newDomainAccess = v; rerenderPanel(); },
};

const PROFILE_ACTIONS = {
  'keep-model': (b) => edit((d) => {
    d.model = b.dataset.v;
    if (d.model === 'profiles') { d.sandbox = null; d.network = null; } else d.active = null;
    return d;
  }),
  'profile-menu': (b) => {
    const named = state.draft.profiles.map((p) => ({ label: p.name, value: p.name, checked: p.name === state.draft.active }));
    const builtins = BUILTIN.map((x) => ({ label: x.v, value: x.v, tone: x.warn ? 'warn' : null, checked: x.v === state.draft.active }));
    openMenu(b, [{ head: 'Your profiles' }, ...named, { sep: true }, { head: 'Built in' }, ...builtins], (it) => edit((d) => { d.active = it.value; return d; }));
  },
  'extends-menu': (b) => {
    const cur = profileOf(state.draft, state.draft.active).extends;
    openMenu(b, b.dataset.parents.split(',').map((v) => ({ label: v, value: v, checked: v === cur })), (it) => editProfile((p) => { p.extends = it.value; }));
  },
  'rm-fs': (b) => editProfile((p) => { p.fs = p.fs.filter((f) => f.p !== b.dataset.p); }),
  'add-fs': () => {
    const raw = (state.form.fs ?? '').trim();
    const p = raw.startsWith('~') || raw.startsWith('/') || raw.startsWith(':') ? raw : `:workspace_roots/${raw}`;
    state.form = { ...state.form, fs: '' };
    editProfile((prof) => { if (!prof.fs.some((f) => f.p === p)) prof.fs.push({ p, a: state.form.newAccess ?? 'read' }); });
  },
  'net-enabled': () => editProfile((p) => { p.net.enabled = !p.net.enabled; }),
  'net-proxy': () => editProfile((p) => { p.net.proxy = !p.net.proxy; }),
  'rm-domain': (b) => editProfile((p) => { p.net.domains = p.net.domains.filter((x) => x.h !== b.dataset.h); }),
  'add-domain': () => {
    const h = (state.form.domain ?? '').trim();
    state.form = { ...state.form, domain: '' };
    editProfile((p) => { if (!p.net.domains.some((x) => x.h === h)) p.net.domains.push({ h, a: state.form.newDomainAccess ?? 'allow' }); });
  },
};
