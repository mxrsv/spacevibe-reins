'use strict';
/* C′ mock: the panel's contents, the Markdown preview, Advanced text and validation, and the list of unsaved changes. */

/* ---------- Rendering: panel ---------- */
function panel() {
  const { agent, section } = state.open;
  const scope = currentScope(agent, section);
  const path = state.open.file ? state.open.file.path : filePath(agent, section, scope);
  const scopes = scopesFor(agent, section);
  const tools = [];
  tools.push(`<button class="scope" data-act="scope-menu" ${scopes.length < 2 ? 'disabled' : ''} aria-haspopup="menu">${esc(scopeLabel(agent, section, scope))}${icon('updown', 'i14')}</button>`);
  tools.push(`<span class="path code trunc" title="${esc(path)}">${esc(path)}</span>`);
  if (section === 'rules') tools.push(seg('rules-mode', [{ v: 'edit', l: 'Edit' }, { v: 'preview', l: 'Preview' }], state.rulesMode, 'on-well'),
    `<button class="btn icon" data-act="toast" data-msg="Opens ${esc(path)} in your editor" aria-label="Open in editor" title="Open in editor">${icon('external')}</button>`);
  else tools.push(`<button class="btn icon" data-act="toast" data-msg="Shows ${esc(path)} in Finder" aria-label="Show in Finder" title="Show in Finder">${icon('folder')}</button>`);
  const body = BODIES[section](agent, scope);
  return `<div class="grip" data-grip role="separator" aria-orientation="vertical" aria-label="Resize panel" tabindex="0"></div>
    <header class="p-head"><span class="mark sm cli-${agent}"><i></i></span><span class="grow" style="display:flex;align-items:baseline;gap:8px;min-width:0"><h2 class="title" style="margin:0" id="ptitle" tabindex="-1">${SECTIONS[section].title}</h2><span class="caption t3 trunc">${CLI[agent].name}</span></span>
    <button class="btn icon" data-act="close" aria-label="Close panel" title="Close (Esc)">${icon('close')}</button></header>
    <div class="p-tools">${tools.join('')}</div>
    ${state.open.file ? `<div class="p-tools crumbs caption" style="margin-top:-8px"><button data-act="back-file">${esc(fileName(filePath(agent, section, scope)))}</button>${icon('arrowRight', 'i14')}<span class="code">${esc(fileName(path))}</span></div>` : ''}
    <div class="p-body${section === 'advanced' || (section === 'rules' && state.rulesMode === 'edit') ? ' wide' : ''}" id="pbody">${body}</div>${footer()}`;
}

function seg(name, options, value, extra = '') {
  return `<div class="seg ${extra}" role="radiogroup">${options.map((o) => `<button role="radio" data-act="seg" data-name="${name}" data-v="${o.v ?? ''}" aria-pressed="${o.v === value}" aria-checked="${o.v === value}" class="${o.warn ? 'warn-opt' : ''}"${o.tone ? ` data-tone="${o.tone}"` : ''}>${o.warn && o.v === value ? icon('warning', 'i14') : ''}${o.l}</button>`).join('')}</div>`;
}
const tagHTML = (map, v, { button = false, data = '' } = {}) => button
  ? `<button class="tag ${map[v].tone}" ${data} aria-haspopup="menu"><i></i>${map[v].l}${icon('chevronDown')}</button>`
  : `<span class="tag ${map[v].tone}"><i></i>${map[v].l}</span>`;
const cardHead = (title, { count, detail, accessory = '' } = {}) => `<div class="card-head"><span class="grow"><span class="title">${title}</span>${count != null ? `<span class="num">${count}</span>` : ''}${detail ? `<span class="code t3 trunc">${esc(detail)}</span>` : ''}</span>${accessory}</div>`;
const field = (name, placeholder, { code = true, value = state.form[name] ?? '', type = 'text', err = false } = {}) => `<label class="field${code ? ' code' : ''}${err ? ' err' : ''}"><input type="${type}" data-in="${name}" value="${esc(value)}" placeholder="${esc(placeholder)}" aria-label="${esc(placeholder)}" spellcheck="false" autocomplete="off"></label>`;
const addBtn = (act, name, label = 'Add') => `<button class="btn" data-act="${act}" data-add-for="${name}" ${(state.form[name] ?? '').trim() ? '' : 'disabled'}>${label}${keycap('↵')}</button>`;
const errLine = (name) => state.form[`${name}:err`] ? `<div class="err-line caption" role="alert">${esc(state.form[`${name}:err`])}</div>` : '';

const BODIES = {
  rules(agent) {
    const text = state.draft;
    if (state.rulesMode === 'edit') return `<div class="editor prose"><textarea data-in="text" spellcheck="false" aria-label="File content" placeholder="Write instructions for ${CLI[agent].name} in Markdown">${esc(text)}</textarea></div>`;
    if (!text.trim()) return `<div class="card"><div class="empty"><p class="row-title" style="margin:0 0 4px;color:var(--text)">This file is empty</p><p class="caption" style="margin:0 0 16px">${CLI[agent].name} reads it at the start of every session once it has content.</p><button class="btn" data-act="seg" data-name="rules-mode" data-v="edit">${icon('edit')}Write it</button></div></div>`;
    return `<div class="md">${markdown(text)}</div>`;
  },

  permissions(agent, scope) {
    const d = state.draft;
    if (agent === 'claude') {
      const inherit = scope !== 'global';
      const mode = MODES.find((m) => m.v === d.mode);
      const desc = mode ? mode.d : `Uses Global: ${MODES.find((m) => m.v === readSaved('claude', 'permissions', 'global').mode).l}.`;
      const groups = ['allow', 'ask', 'deny'].map((v) => {
        const rows = d.rules.filter((r) => r.v === v);
        if (!rows.length) return '';
        return `<div class="section-row"><span class="label t2">${VERDICT[v].l}</span><span class="caption t3 num">${rows.length}</span></div>` +
          (rows.length ? rows.map((r) => `<div class="row"><span class="grow"><span class="code-title trunc" title="${esc(r.p)}">${esc(r.p)}</span></span>${tagHTML(VERDICT, r.v, { button: true, data: `data-act="verdict-menu" data-p="${esc(r.p)}"` })}<span class="acts"><button class="btn icon" data-act="rm-rule" data-p="${esc(r.p)}" aria-label="Remove ${esc(r.p)}">${icon('trash')}</button></span></div>`).join('')
            : '');
      }).join('') || `<div class="note caption">No rules in ${esc(filePath('claude', 'permissions', scope))} yet.</div>`;
      const modeLabel = mode ? mode.l : `Same as Global (${MODES.find((m) => m.v === readSaved('claude', 'permissions', 'global').mode).l})`;
      return `<div class="card"><div class="card-head" style="min-height:48px"><span class="grow"><span class="title">Default mode</span><span class="code t3">defaultMode</span></span></div>
          <div style="padding:0 16px 8px"><button class="scope${mode?.warn ? ' warn' : ''}" style="width:100%;background:var(--raised)" data-act="mode-menu" aria-haspopup="menu">${mode?.warn ? icon('warning', 'i14') : ''}${esc(modeLabel)}${icon('updown', 'i14')}</button><p class="caption ${mode?.warn ? 'warn' : 't3'}" style="margin:8px 0 0">${esc(desc)}</p></div></div>
        <div class="card">${cardHead('Rules', { count: d.rules.length, detail: 'permissions' })}
          <div class="add-row two">${field('rule', 'Bash(npm run build:*)', { err: !!state.form['rule:err'] })}${seg('new-verdict', [{ v: 'allow', l: 'Allow', tone: 'ok' }, { v: 'ask', l: 'Ask', tone: 'warn' }, { v: 'deny', l: 'Deny', tone: 'bad' }], state.form.newVerdict ?? 'allow')}${addBtn('add-rule', 'rule')}</div>${errLine('rule')}${groups}</div>
        <div class="card">${cardHead('Extra folders', { count: d.dirs.length, detail: 'additionalDirectories' })}
          <div class="add-row">${field('dir', '~/path/to/folder')}${addBtn('add-dir', 'dir')}</div>
          ${d.dirs.length ? d.dirs.map((p) => `<div class="row lead"><span class="lead-ic">${icon('folder', 'i20')}</span><span class="grow"><span class="code-title trunc" title="${esc(p)}">${esc(p)}</span></span><span class="acts"><button class="btn icon" data-act="rm-dir" data-p="${esc(p)}" aria-label="Remove ${esc(p)}">${icon('trash')}</button></span></div>`).join('') : `<div class="note caption">Claude Code works only in the folder it starts in.</div>`}</div>`;
    }
    if (scope !== 'global') {
      const p = scope.split(':')[1];
      return `<div class="card">${cardHead('Trust', { detail: 'trust_level' })}<div style="padding:0 16px 8px">${seg('trust', TRUST, d.trust, 'full')}<p class="caption t3" style="margin:8px 0 0">Only trust is set per project. Sandbox, approval and command rules come from Global.</p></div></div>
        <button class="btn" style="align-self:flex-start" data-act="go-scope" data-scope="global">Open Global</button>`;
    }
    const st = codexStatus(d);
    const rows = d.rules.map((r) => `<div class="row"><span class="grow"><span class="code-title trunc">${esc(r.p)}</span><span class="caption t3">prefix_rule</span></span>${tagHTML(DECISION, r.d, { button: true, data: `data-act="decision-menu" data-p="${esc(r.p)}"` })}<span class="acts"><button class="btn icon" data-act="rm-cmd" data-p="${esc(r.p)}" aria-label="Remove ${esc(r.p)}">${icon('trash')}</button></span></div>`).join('');
    return `<div class="lead-block"><span class="lead-tile${st.warn ? ' warn' : ''}">${icon(st.warn ? 'warning' : 'check', 'i20')}</span><span style="display:flex;flex-direction:column;min-width:0"><span class="row-title">${esc(st.sentence)}</span><span class="code t3">${esc(st.code)}</span></span></div>
      <div class="card">${cardHead('How Codex runs', { detail: 'config.toml' })}
        <div class="row stack static"><span class="grow"><span class="row-title">Asks before acting</span><span class="code t3">approval_policy</span></span>${seg('approval', APPROVAL, d.approval, 'full')}${d.approval === 'never' ? `<span class="caption warn">${WARN.never}</span>` : ''}</div>
        <div class="row stack static"><span class="grow"><span class="row-title">Sandbox</span><span class="code t3">sandbox_mode</span></span>${seg('sandbox', SANDBOX, d.sandbox, 'full')}${d.sandbox === 'danger-full-access' ? `<span class="caption warn">${WARN.full}</span>` : ''}</div>
        ${d.sandbox === 'workspace-write' ? `<div class="row static"><span class="grow"><span class="row-title">Network</span><span class="code t3">sandbox_workspace_write.network_access</span></span><button class="switch" role="switch" aria-checked="${d.network}" aria-label="Network" data-act="network"></button></div>
        <div class="row stack static"><span class="grow"><span class="row-title">Can also write to</span><span class="code t3">sandbox_workspace_write.writable_roots</span></span>
          ${d.roots.length ? `<div class="chips">${d.roots.map((p) => `<span class="chip"><span class="code">${esc(p)}</span><button class="btn icon" style="width:20px;height:20px;margin-right:-6px" data-act="rm-root" data-p="${esc(p)}" aria-label="Remove ${esc(p)}">${icon('close', 'i14')}</button></span>`).join('')}</div>` : ''}
          <div style="display:flex;gap:8px">${field('root', '~/path/to/folder')}${addBtn('add-root', 'root')}</div></div>` : ''}
      </div>
      <div class="card">${cardHead('Command rules', { count: d.rules.length, detail: '~/.codex/rules/default.rules' })}
        <div class="add-row two">${field('cmd', 'npm publish', { err: !!state.form['cmd:err'] })}${seg('new-decision', [{ v: 'allow', l: 'Allow', tone: 'ok' }, { v: 'prompt', l: 'Prompt', tone: 'warn' }, { v: 'forbidden', l: 'Forbidden', tone: 'bad' }], state.form.newDecision ?? 'prompt')}${addBtn('add-cmd', 'cmd')}</div>${errLine('cmd')}
        ${rows || `<div class="note caption">No command rules yet.</div>`}</div>`;
  },

  hooks(agent) {
    const d = state.draft;
    const dead = d.filter((h) => h.dead).length;
    const acc = `${dead ? `<button class="btn danger" data-act="rm-dead">${icon('trash')}Remove ${dead} dead</button>` : ''}<button class="btn" data-act="toggle-add" data-what="hook" aria-expanded="${state.adding === 'hook'}">${icon('add')}Add hook</button>`;
    const form = state.adding === 'hook' ? `<div class="row stack static" style="margin-bottom:4px"><div style="display:flex;gap:8px"><button class="scope" style="background:var(--raised)" data-act="event-menu" aria-haspopup="menu">${esc(state.form.event ?? EVENTS[agent][0])}${icon('updown', 'i14')}</button>${field('matcher', 'Matcher, e.g. Bash')}</div><div style="display:flex;gap:8px">${field('command', 'Command to run, e.g. ~/.claude/hooks/check.sh')}${addBtn('add-hook', 'command')}</div></div>` : '';
    const rows = d.map((h) => {
      const right = h.dead ? `<span class="tag bad">${icon('warning', 'i14')}script missing</span>`
        : h.runs == null ? `<span class="tag">${icon('warning', 'i14')}not measurable</span>`
          : `${h.errors ? `<span class="tag warn"><i></i>${fmt(h.errors)} errors</span>` : ''}<span class="num t2" style="min-width:52px;text-align:right">${fmt(h.runs)}</span>`;
      return `<div class="row lead"><span class="lead-ic">${icon('hooks', 'i20')}</span><span class="grow"><span class="row-title trunc">${esc(h.event)}${h.matcher ? ` · ${esc(h.matcher)}` : ''}</span><span class="code t3 trunc" title="${esc(h.cmd)}">${esc(h.cmd)}</span></span>${right}
        <span class="acts over"><button class="btn icon" data-act="copy-hook" data-id="${h.id}" aria-label="Copy to ${CLI[CLI[agent].other].name}" title="Copy to ${CLI[CLI[agent].other].name}">${icon('copy')}</button><button class="btn icon" data-act="rm-hook" data-id="${h.id}" aria-label="Remove hook">${icon('trash')}</button></span></div>`;
    }).join('');
    return `<div class="card">${cardHead('Hooks', { count: d.length, accessory: acc })}${form}${rows || `<div class="empty caption">No hooks in this file yet.</div>`}
      ${agent === 'codex' ? `<div class="note caption">Codex does not log hook runs, so Reins cannot count them.</div>` : `<div class="note caption">Runs counted from ${SESSIONS.claude} sessions since 2026-10-05.</div>`}</div>`;
  },

  mcp(agent, scope) {
    const d = state.draft;
    const form = state.adding === 'mcp' ? `<div class="row stack static" style="margin-bottom:4px"><div style="display:flex;gap:8px">${field('mcpName', 'Name')}${seg('mcp-type', [{ v: 'stdio', l: 'Command' }, { v: 'http', l: 'URL' }], state.form.mcpType ?? 'stdio')}</div><div style="display:flex;gap:8px">${field('mcpTarget', (state.form.mcpType ?? 'stdio') === 'stdio' ? 'npx -y some-mcp-server' : 'https://example.com/mcp')}${addBtn('add-mcp', 'mcpTarget')}</div></div>` : '';
    const rows = d.map((m) => {
      const open = state.expanded.has(m.name);
      const secrets = open ? m.secrets.map((s) => {
        const f = `secret:${m.name}:${s.k}`;
        const editing = state.form[`${f}:open`];
        return `<div class="row static" style="margin-left:28px"><span class="grow"><span class="code-title trunc" title="${esc(s.k)}">${esc(s.k)}</span><span class="code t3">${s.replaced ? 'new value set, not shown' : '••••••••'}</span></span>
          ${editing ? `<div style="display:flex;gap:8px;width:220px">${field(f, 'New value', { type: 'password' })}<button class="btn" data-act="set-secret" data-mcp="${esc(m.name)}" data-k="${esc(s.k)}">Set</button></div>` : `<button class="btn" data-act="replace-secret" data-f="${esc(f)}">${icon('key')}Replace</button>`}</div>`;
      }).join('') + (m.secrets.length ? '' : `<div class="note caption" style="padding-left:64px">No secrets.</div>`) : '';
      const lock = m.plugin ? `<span class="tag">${icon('lock', 'i14')}plugin: ${esc(m.plugin)}</span>` : '';
      return `<div class="row lead"><button class="lead-ic" data-act="expand" data-name="${esc(m.name)}" aria-expanded="${open}" aria-label="${open ? 'Hide' : 'Show'} details of ${esc(m.name)}" style="transform:rotate(${open ? 0 : -90}deg);transition:transform .15s">${icon('chevronDown', 'i14')}</button>
        <span class="grow"><span class="row-title">${esc(m.name)} <span class="caption t3">${m.type === 'stdio' ? 'command' : 'URL'}</span></span><span class="code t3 trunc" title="${esc(m.target)}">${esc(m.target)}</span></span>${lock}${m.secrets.length ? `<span class="tag">${icon('key', 'i14')}${m.secrets.length}</span>` : ''}
        ${m.plugin ? '' : `<span class="acts over"><button class="btn icon" data-act="rm-mcp" data-name="${esc(m.name)}" aria-label="Remove ${esc(m.name)}">${icon('trash')}</button></span>`}</div>${secrets}`;
    }).join('');
    const where = agent === 'claude' ? (scope === 'global' ? 'Available in every project' : scope.startsWith('local') ? 'Only you, only in this project' : 'Shared with the project in .mcp.json') : 'Available in every project';
    return `<div class="card">${cardHead('Servers', { count: d.length, detail: where, accessory: `<button class="btn" data-act="toggle-add" data-what="mcp" aria-expanded="${state.adding === 'mcp'}">${icon('add')}Add server</button>` })}${form}${rows || `<div class="empty caption">No MCP servers here yet.</div>`}</div>`;
  },

  model(agent, scope) {
    const d = state.draft;
    const inherited = scope !== 'global' ? readSaved(agent, 'model', 'global').model : null;
    const chips = MODEL_LOG[agent].map(([m, n]) => `<button class="chip" data-act="pick-model" data-m="${m}" aria-pressed="${d.model === m}"><span class="code">${m}</span><span class="c">${n}</span></button>`).join('');
    return `<div class="card">${cardHead('Model', { detail: 'model' })}<div style="padding:0 16px 8px;display:flex;flex-direction:column;gap:12px">
        ${field('model', inherited ? `Same as Global (${inherited})` : 'Model name', { value: d.model ?? '' })}
        <div class="chips">${chips}</div><span class="caption t3">Sessions per model in your logs since 2026-10-05.</span></div></div>
      ${agent === 'codex' ? `<div class="card">${cardHead('Reasoning effort', { detail: 'model_reasoning_effort' })}<div style="padding:0 16px 8px">${seg('effort', EFFORT, d.effort, 'full')}</div></div>` : ''}`;
  },

  advanced(agent) {
    const lines = state.draft.split('\n').length;
    return `<div class="editor"><div class="gutter" id="gutter" aria-hidden="true">${Array.from({ length: lines }, (_, i) => i + 1).join('<br>')}</div><textarea data-in="text" spellcheck="false" aria-label="${agent === 'claude' ? 'settings.json' : 'config.toml'}" wrap="off">${esc(state.draft)}</textarea></div>
      <div class="status-line caption" id="status">${statusLine(agent)}</div>`;
  },
};

function statusLine(agent) {
  const err = validate(agent, state.draft);
  const lang = agent === 'claude' ? 'JSON' : 'TOML';
  return err ? `<span class="tag bad"><i></i>${esc(err)}</span>` : `<span class="tag ok"><i></i>Valid ${lang}</span><span>Secret values show as •••• and stay as they are when you save.</span>`;
}

function footer() {
  if (state.ask) {
    return `<div class="p-foot ask" id="pfoot" role="alertdialog" aria-label="Unsaved changes"><span class="grow row-title warn">Discard ${plural(changes().length, 'change')}?</span><button class="btn" style="--btn-ground:var(--surface)" data-act="keep">Keep editing${keycap('Esc')}</button><button class="btn danger" style="--btn-ground:var(--surface)" data-act="discard">Discard</button></div>`;
  }
  if (!isDirty()) return '<div id="pfoot" hidden></div>';
  const n = changes().length;
  const invalid = state.open.section === 'advanced' && validate(state.open.agent, state.draft);
  return `<div class="p-foot" id="pfoot"><span class="grow row-title">${plural(n, 'unsaved change')}</span><button class="btn" style="--btn-ground:var(--raised)" data-act="discard">Discard</button><button class="btn primary" data-act="review" ${invalid ? 'disabled' : ''}>Review and save${keycap('⌘S')}</button></div>`;
}

/* ---------- Markdown preview ---------- */
function inline(s) {
  return esc(s).replace(/`([^`]+)`/g, '<code>$1</code>').replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
}
function markdown(text) {
  const out = []; let list = null;
  const flush = () => { if (list) { out.push(`<ul>${list.join('')}</ul>`); list = null; } };
  for (const line of text.split('\n')) {
    const t = line.trim();
    if (/^@\S+/.test(t)) {
      flush();
      const path = t.slice(1);
      const lines = (IMPORTS[path] ?? '').split('\n').length;
      out.push(`<button class="import" data-act="open-import" data-path="${esc(path)}">${icon('link', 'i20')}<span class="grow"><span class="code-title">${esc(fileName(path))}</span><span class="code t3 trunc">${esc(path)} · ${IMPORTS[path] ? `${lines} lines` : 'not found'}</span></span>${icon('arrowRight')}</button>`);
    } else if (/^#{1,3} /.test(t)) { flush(); const lvl = t.match(/^#+/)[0].length; out.push(`<h${lvl === 1 ? 1 : 2}>${inline(t.replace(/^#+ /, ''))}</h${lvl === 1 ? 1 : 2}>`); }
    else if (/^- /.test(t)) { (list ??= []).push(`<li>${inline(t.slice(2))}</li>`); }
    else if (t) { flush(); out.push(`<p>${inline(t)}</p>`); }
    else flush();
  }
  flush();
  return out.join('');
}

/* ---------- Advanced: generated text and validation ---------- */
function advancedText(agent, scope) {
  if (agent === 'codex') {
    const p = readSaved('codex', 'permissions', 'global'), m = readSaved('codex', 'model', 'global'), servers = readSaved('codex', 'mcp', 'global');
    const out = [`model = "${m.model}"`, `model_reasoning_effort = "${m.effort}"`, `approval_policy = "${p.approval}"`, `sandbox_mode = "${p.sandbox}"`, '', '[sandbox_workspace_write]', `network_access = ${p.network}`];
    if (p.roots.length) out.push(`writable_roots = [${p.roots.map((r) => `"${r}"`).join(', ')}]`);
    for (const s of servers) {
      out.push('', `[mcp_servers.${s.name}]`);
      if (s.type === 'stdio') { const [cmd, ...args] = s.target.split(' '); out.push(`command = "${cmd}"`, `args = [${args.map((a) => `"${a}"`).join(', ')}]`); } else out.push(`url = "${s.target}"`);
      if (s.secrets.length) out.push('', `[mcp_servers.${s.name}.env]`, ...s.secrets.map((x) => `${x.k} = "••••"`));
    }
    out.push('', '[profiles.deep]', 'model_reasoning_effort = "high"');
    for (const proj of PROJECTS) { const t = readSaved('codex', 'permissions', `project:${proj}`).trust; if (t) out.push('', `[projects."/Users/dev/Developer/${proj}"]`, `trust_level = "${t}"`); }
    return out.join('\n') + '\n';
  }
  const p = readSaved('claude', 'permissions', scope), m = readSaved('claude', 'model', scope), hooks = readSaved('claude', 'hooks', scope);
  const obj = {};
  if (scope === 'global') obj.$schema = 'https://json.schemastore.org/claude-code-settings.json';
  if (m.model) obj.model = m.model;
  if (scope === 'global') obj.env = { ANTHROPIC_API_KEY: '••••', DISABLE_TELEMETRY: '••••' };
  const perms = {};
  if (p.mode) perms.defaultMode = p.mode;
  for (const v of ['allow', 'ask', 'deny']) { const r = p.rules.filter((x) => x.v === v).map((x) => x.p); if (r.length) perms[v] = r; }
  if (p.dirs.length) perms.additionalDirectories = p.dirs;
  if (Object.keys(perms).length) obj.permissions = perms;
  if (hooks.length) {
    obj.hooks = {};
    for (const h of hooks) (obj.hooks[h.event] ??= []).push({ ...(h.matcher ? { matcher: h.matcher } : {}), hooks: [{ type: 'command', command: h.cmd }] });
  }
  if (scope === 'global') { obj.statusLine = { type: 'command', command: '~/.claude/statusline.sh' }; obj.enabledPlugins = { 'neon@claude-plugins-official': true }; }
  return JSON.stringify(obj, null, 2) + '\n';
}
function validate(agent, text) {
  if (agent === 'claude') {
    if (!text.trim()) return null;
    try { JSON.parse(text); return null; } catch (e) {
      const pos = Number((/position (\d+)/.exec(e.message) || [])[1]);
      const line = Number.isFinite(pos) ? text.slice(0, pos).split('\n').length : null;
      const msg = e.message.replace(/ in JSON.*$/, '').replace(/^JSON\.parse: /, '');
      return line ? `Line ${line}: ${msg}` : msg;
    }
  }
  let depth = 0;
  const lines = text.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const t = lines[i].replace(/#.*$/, '').trim();
    const open = (t.match(/\[/g) || []).length - (t.match(/\]/g) || []).length;
    if (depth > 0) { depth += open; continue; }
    if (!t) continue;
    if (/^\[\[?[^\[\]]+\]\]?$/.test(t)) continue;
    const kv = /^("[^"]*"|[A-Za-z0-9_.-]+)\s*=\s*(.*)$/.exec(t);
    if (!kv) return `Line ${i + 1}: expected key = value`;
    const v = kv[2];
    if (!v) return `Line ${i + 1}: missing value`;
    if (/^"/.test(v) && !/^"(?:[^"\\]|\\.)*"\s*$/.test(v) && !/^"""/.test(v)) return `Line ${i + 1}: unclosed string`;
    if (!/^("|'|\[|\{|true\b|false\b|[+-]?\d)/.test(v)) return `Line ${i + 1}: a text value needs quotes`;
    if (/^\[/.test(v)) depth = open;
  }
  return depth > 0 ? 'An array is not closed' : null;
}

/* ---------- Changes ---------- */
const isDirty = () => !!state.open && !same(state.draft, state.base);
function changes() {
  if (!state.open) return [];
  const { agent, section } = state.open, a = state.base, b = state.draft;
  const out = [];
  const listDiff = (xs, ys, key, val, describe) => {
    const am = new Map(xs.map((x) => [key(x), x])), bm = new Map(ys.map((y) => [key(y), y]));
    for (const [k, y] of bm) { if (!am.has(k)) out.push({ op: 'Add', ...describe(y) }); else if (val && val(am.get(k)) !== val(y)) out.push({ op: 'Change', from: describe(am.get(k)), ...describe(y) }); }
    for (const [k, x] of am) if (!bm.has(k)) out.push({ op: 'Remove', ...describe(x) });
  };
  if (typeof a === 'string') {
    if (a !== b) {
      const al = a.split('\n'), bl = b.split('\n');
      let changed = 0; for (let i = 0; i < Math.max(al.length, bl.length); i++) if (al[i] !== bl[i]) changed++;
      out.push({ op: 'Edit', text: `${plural(changed, 'line')} in ${fileName(state.open.file?.path ?? filePath(agent, section, currentScope(agent, section)))}` });
    }
    return out;
  }
  if (section === 'permissions' && agent === 'claude') {
    if (a.mode !== b.mode) out.push({ op: 'Change', text: `defaultMode → ${b.mode ?? 'same as Global'}`, warn: b.mode === 'bypassPermissions' ? WARN.bypass : null });
    listDiff(a.rules, b.rules, (r) => r.p, (r) => r.v, (r) => ({ tag: VERDICT[r.v], text: r.p }));
    listDiff(a.dirs.map((p) => ({ p })), b.dirs.map((p) => ({ p })), (r) => r.p, null, (r) => ({ text: r.p }));
  } else if (section === 'permissions') {
    if (a.trust !== b.trust) out.push({ op: 'Change', text: `trust_level → ${b.trust ?? 'not set'}` });
    if (a.approval !== b.approval) out.push({ op: 'Change', text: `approval_policy → "${b.approval}"`, warn: b.approval === 'never' ? WARN.never : null });
    if (a.sandbox !== b.sandbox) out.push({ op: 'Change', text: `sandbox_mode → "${b.sandbox}"`, warn: b.sandbox === 'danger-full-access' ? WARN.full : null });
    if (a.network !== b.network) out.push({ op: 'Change', text: `network_access → ${b.network}` });
    if (a.roots) listDiff(a.roots.map((p) => ({ p })), b.roots.map((p) => ({ p })), (r) => r.p, null, (r) => ({ text: r.p }));
    if (a.rules) listDiff(a.rules, b.rules, (r) => r.p, (r) => r.d, (r) => ({ tag: DECISION[r.d], text: r.p }));
  } else if (section === 'hooks') {
    listDiff(a, b, (h) => h.id, null, (h) => ({ text: `${h.event}${h.matcher ? ` · ${h.matcher}` : ''}: ${h.cmd}` }));
  } else if (section === 'mcp') {
    listDiff(a, b, (m) => m.name, null, (m) => ({ text: `${m.name} (${m.target})` }));
    for (const m of b) for (const s of m.secrets) if (s.replaced) out.push({ op: 'Replace', text: `${m.name} · ${s.k} (value not shown)` });
  } else if (section === 'model') {
    if (a.model !== b.model) out.push({ op: 'Change', text: `model → ${b.model ? `"${b.model}"` : 'same as Global'}` });
    if (a.effort !== b.effort) out.push({ op: 'Change', text: `model_reasoning_effort → "${b.effort}"` });
  }
  return out;
}

