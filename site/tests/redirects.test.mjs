// Redirects in vercel.json (output: "export" rules out next.config redirects). No network.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative, sep } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("..", import.meta.url));
const { redirects } = JSON.parse(readFileSync(join(root, "vercel.json"), "utf8"));

const SITE_HOSTS = new Set(["spacevibe.dev", "www.spacevibe.dev"]);
const LIVE_TARGET = "https://active.spacevibe.dev";
const KYANT = "https://kyant.dev";

/** The subset of path-to-regexp that vercel.json sources here use: literals, `:name`, `:name*`. */
function toRegExp(source) {
  const body = source
    .split("/")
    .filter(Boolean)
    .map((seg) => {
      if (/^:\w+\*$/.test(seg)) return "(?:/.*)?";
      if (/^:\w+$/.test(seg)) return "/[^/]+";
      return `/${seg.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`;
    })
    .join("");
  return new RegExp(`^${body || "/"}$`);
}

const match = (source, path) => toRegExp(source).test(path);
const redirectFor = (path) => redirects.find((r) => match(r.source, path));

function walk(dir) {
  return readdirSync(dir).flatMap((name) => {
    const full = join(dir, name);
    return statSync(full).isDirectory() ? walk(full) : [full];
  });
}

/** Routes the static site serves: app/**\/page.* and route.*, files in app/ (favicon), and public/. */
function servedRoutes() {
  const routes = new Set();
  const app = join(root, "app");
  for (const file of walk(app)) {
    const rel = relative(app, file).split(sep);
    const name = rel.pop();
    const dir = rel.filter((s) => !/^\(.*\)$/.test(s)).join("/");
    if (/^(page|route)\.(tsx?|jsx?)$/.test(name)) routes.add(`/${dir}`);
    else if (!/\.(css|tsx?|jsx?)$/.test(name)) routes.add(`/${[dir, name].filter(Boolean).join("/")}`);
  }
  const pub = join(root, "public");
  for (const file of walk(pub)) routes.add(`/${relative(pub, file).split(sep).join("/")}`);
  return routes;
}

test("the live family goes to active.spacevibe.dev with a 308", () => {
  const live = { "/live": "/", "/en/live": "/", "/vi/live": "/", "/live/abc": "/abc", "/en/live/abc": "/abc", "/vi/live/abc/x": "/abc/x" };
  for (const [path, tail] of Object.entries(live)) {
    const rule = redirectFor(path);
    assert.ok(rule, `${path} has a rule`);
    assert.equal(rule.permanent, true, `${path} is permanent (308)`);
    const dest = rule.destination.replace(/:slug\*$/, tail.replace(/^\//, ""));
    assert.equal(dest, `${LIVE_TARGET}${tail}`, path);
  }
});

test("old Hub routes keep their path on kyant.dev", () => {
  for (const path of ["/deck", "/free-tier", "/vote", "/vote/privacy", "/en", "/en/deck", "/en/free-tier", "/vi/deck", "/vote/opengraph-image"]) {
    const rule = redirectFor(path);
    assert.ok(rule, `${path} has a rule`);
    assert.equal(rule.permanent, true, path);
    assert.equal(rule.destination, `${KYANT}${path}`, path);
  }
  for (const path of ["/api/vote", "/api/vote/me", "/api/auth/callback/google"]) {
    assert.ok(redirectFor(path)?.destination.startsWith(`${KYANT}/api/`), path);
  }
});

test("no rule shadows a route the site serves", () => {
  const served = servedRoutes();
  assert.ok(served.has("/") && served.has("/directions"), "served routes were derived from app/");
  for (const path of served) {
    const rule = redirectFor(path);
    assert.equal(rule, undefined, `${path} is served by this site but matches ${rule?.source}`);
  }
});

test("no redirect loops", () => {
  for (const { source, destination } of redirects) {
    const url = new URL(destination);
    assert.equal(url.protocol, "https:", source);
    assert.ok(!SITE_HOSTS.has(url.hostname), `${source} sends traffic back to this site`);
    const params = [...destination.matchAll(/:(\w+)/g)].map((m) => m[1]);
    for (const p of params) assert.ok(source.includes(`:${p}`), `${source}: destination uses :${p} the source lacks`);
  }
});
