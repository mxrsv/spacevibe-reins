// SVG path data as the absolute move, line, cubic and close commands the generated Swift draws, and those commands as
// `GlyphPen` calls. Shared by both icon sources of scripts/generate-icons.mjs (Solar for the sidebar, Tabler for pages).
// H and V become lines, Q, T and S become cubics, and arcs are split into cubics of at most 90 degrees.

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

// MARK: Swift

export const num = (v) => {
  const s = String(Number(v.toFixed(3)));
  return s === '-0' ? '0' : s;
};

export function swiftLines(commands) {
  const lines = [];
  let line = [];
  for (const [op, ...args] of commands) {
    if (op === 'M' && line.length) { lines.push(line.join('; ')); line = []; }
    line.push(`p.${op.toLowerCase()}(${args.map(num).join(', ')})`);
  }
  if (line.length) lines.push(line.join('; '));
  return lines;
}
