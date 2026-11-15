// ========================================
// /whip SECTION — Config (and every settings page)
//
// config.lua's settings, edited in game. The server (server/settings.lua) sends each page as
// groups of settings, each with the value in force, config.lua's default, what is saved (when a
// change waits for a restart, the two differ) and who changed it last. Edits are held here until
// Apply, which sends them all at once; the server checks every one, saves them in one go, puts the
// live ones in force on the server and every player, and the panel redraws from what it then holds.
//
// makeSettingsSection builds one page's section, so a satellite's settings page (Whip.configPage)
// is the same renderer with another owner. Only permanent admins see these sections
// (permanentOnly); the server refuses anyone else regardless.
//
// Values cross the wire in shared/settings.lua's form: { $nil: true } for "none", { $v: [x, y, z] }
// for a vector. decode/encode below speak it.
// ========================================

import { WhipPanel, WP } from '../whip-panel.js';
import { nuiCallback } from '../utils.js';
import { screenRect } from '../pad-cursor.js';
import { number } from './format.js';
import { BLIP_COLOURS } from './pickers.js';

// A vector's axes to 3 places: the game keeps them as 32-bit floats (-360.96 comes back as
// -360.9599914…), and an admin typing the same number again must not read as a change.
const r3 = (n) => (typeof n === 'number' ? Math.round(n * 1000) / 1000 : n);

// All the way down: a row of a list can hold a vector, and a map keyed by model number comes as
// { $map: [[key, value], ...] } — read here as an object keyed by the number as text, which is how
// the panel shows and sends it (the server turns it back into the number).
function decode(v) {
    if (Array.isArray(v)) return v.map(decode);
    if (v && typeof v === 'object') {
        if (v.$nil === true) return null;
        if (Array.isArray(v.$v)) {
            const [x, y, z, w] = v.$v.map(r3);
            return w !== undefined ? { x, y, z, w } : z !== undefined ? { x, y, z } : { x, y };
        }
        if (Array.isArray(v.$map)) {
            const o = {};
            for (const kv of v.$map) if (Array.isArray(kv)) o[String(decode(kv[0]))] = decode(kv[1]);
            return o;
        }
        const o = {};
        for (const k of Object.keys(v)) o[k] = decode(v[k]);
        return o;
    }
    return v === undefined ? null : v;
}

/** A setting's value, decoded. A map whose keys are exactly 1..n travels as a list (the server cannot
 *  tell the two apart); it is read back as rows keyed "1".."n", not as list places 0..n-1. */
function valueOf(s, raw) {
    const v = decode(raw);
    if (s.type === 'map' && Array.isArray(v)) return Object.fromEntries(v.map((x, i) => [String(i + 1), x]));
    return v;
}

const copyOf = (v) => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));

/** A field of a row by its key, which may reach inside it: 'permissions.canHire'. */
function getField(rec, key) {
    let t = rec;
    for (const part of String(key).split('.')) {
        if (!t || typeof t !== 'object') return undefined;
        t = t[part];
    }
    return t;
}

/** Set it; null or undefined takes the field out, as a nil does in the row the server keeps. */
function setField(rec, key, value) {
    const parts = String(key).split('.');
    let t = rec;
    for (let i = 0; i < parts.length - 1; i++) {
        if (!t[parts[i]] || typeof t[parts[i]] !== 'object') t[parts[i]] = {};
        t = t[parts[i]];
    }
    const last = parts[parts.length - 1];
    if (value === null || value === undefined) delete t[last];
    else t[last] = value;
}

/** One row checked against its fields; fields not listed are kept as they are. */
function checkRecord(fields, rec, where) {
    const out = rec && typeof rec === 'object' ? copyOf(rec) : {};
    for (const f of fields) {
        const c = check(f, getField(rec, f.key));
        if (c.why) return { why: (where ? where + ': ' : '') + (f.label || f.key) + ' ' + c.why };
        setField(out, f.key, c.value);
    }
    return { value: out };
}

const AXES = ['x', 'y', 'z', 'w'];
const isVec = (s) => s.type === 'vec3' || s.type === 'vec4';
const axesOf = (s) => AXES.slice(0, s.type === 'vec4' ? 4 : 3);

/** A unit's place: money goes in front ("$500", "$1 per %"), everything else after ("10 m"). */
function unitParts(s) {
    const u = s.unit || '';
    if (u.startsWith('$')) return { before: '$', after: u.slice(1).trim() };
    return { before: '', after: u };
}

/** A value as words, for "Default: …" and the like. */
function describe(s, v) {
    if (v === null || v === undefined) return s.emptyLabel || 'none';
    if (s.type === 'bool') return v ? 'On' : 'Off';
    if (v === false && s.offWhenEmpty) return s.emptyLabel || 'off';
    if (s.type === 'enum') {
        const o = (s.options || []).find((x) => x.value === v);
        return o ? (o.label || String(o.value)) : String(v);
    }
    if (s.type === 'int' || s.type === 'number') {
        const u = unitParts(s);
        // A sign is written against the number ("70°", "1.5×", "100%"); a word after a space.
        const tight = u.after === '°' || u.after === '×' || u.after === '%';
        return u.before + number(v) + (u.after ? (tight ? '' : ' ') + u.after : '');
    }
    if (isVec(s)) return axesOf(s).map((a) => number(v[a])).join(', ');
    if (s.type === 'list' && Array.isArray(v)) {
        if (v.length === 0) return 'none';
        const item = s.item || {};
        return v.map((x) => (typeof x === 'number' ? number(x) : String(x))).join(', ')
            + (item.unit ? ' ' + item.unit : '');
    }
    if (s.type === 'records' && Array.isArray(v)) return v.length === 0 ? 'none' : v.length + ' row' + (v.length === 1 ? '' : 's');
    if (s.type === 'heroShots' && Array.isArray(v)) {
        const n = v.filter(Boolean).length;
        return n + ' shot' + (n === 1 ? '' : 's') + ' made';
    }
    if (s.type === 'map' && typeof v === 'object') {
        const n = Object.keys(v).length;
        return n === 0 ? 'none' : n + ' entr' + (n === 1 ? 'y' : 'ies');
    }
    if (typeof v === 'string') return '"' + v + '"';
    return JSON.stringify(v);
}

/** A list as the admin types it: entries split by commas. Numbers exactly, never rounded: the box
 *  is saved back as it reads. */
function listText(v) {
    if (!Array.isArray(v)) return '';
    return v.map((x) => String(x)).join(', ');
}

/**
 * The server's Lua pattern as a JS RegExp, for the patterns settings use: anchors, sets, + * ?, and
 * the classes %w %a %d %p (ASCII only, as Lua's are) and escaped punctuation. Anything else answers
 * null, and the server alone checks it.
 */
const patternCache = new Map();
function luaPattern(p) {
    if (typeof p !== 'string') return null;
    if (patternCache.has(p)) return patternCache.get(p);
    // %p is ASCII punctuation: ! to /, : to @, [ to `, { to ~.
    const CLASS = { w: 'A-Za-z0-9', a: 'A-Za-z', d: '0-9', x: 'A-Fa-f0-9', u: 'A-Z', l: 'a-z', p: '!-\\/:-@\\[-`{-~' };
    let out = '';
    let inSet = false;
    let ok = true;
    for (let i = 0; i < p.length && ok; i++) {
        const c = p[i];
        if (c === '%') {
            const n = p[++i];
            if (n === undefined) ok = false;
            else if (CLASS[n]) out += inSet ? CLASS[n] : '[' + CLASS[n] + ']';
            else if (/[^A-Za-z0-9]/.test(n)) out += '\\' + n;
            else ok = false;
        } else if (c === '[') { inSet = true; out += c; }
        else if (c === ']') { inSet = false; out += c; }
        else if (c === '^' || c === '$' || c === '+' || c === '*' || c === '?') out += c;
        else if (/[A-Za-z0-9_ ]/.test(c)) out += c;
        else ok = false;
    }
    let re = null;
    if (ok) { try { re = new RegExp(out); } catch (e) { re = null; } }
    patternCache.set(p, re);
    return re;
}

/** The panel's own check, so a mistake shows before Apply. The server checks again. */
function check(s, raw) {
    if (s.type === 'int' || s.type === 'number') {
        if (raw === '' || raw === null || raw === undefined) {
            // An empty box is "off" (false) or "none" (nil) where the setting has one.
            if (s.offWhenEmpty) return { value: false };
            if (s.nullable) return { value: null };
            return { why: 'needs a value' };
        }
        const n = Number(raw);
        if (!Number.isFinite(n)) return { why: 'must be a number' };
        if (s.type === 'int' && !Number.isInteger(n)) return { why: 'must be a whole number' };
        if (s.min !== undefined && s.min !== null && n < s.min) return { why: 'must be at least ' + number(s.min) };
        if (s.max !== undefined && s.max !== null && n > s.max) return { why: 'must be at most ' + number(s.max) };
        return { value: n };
    }
    if (s.type === 'string') {
        // A field a row does not have is empty, never the word "undefined".
        const t = raw === null || raw === undefined ? '' : String(raw).trim();
        // Counted in characters (code points), as the server counts them (utf8.len).
        const len = [...t].length;
        // Empty is "off" (false) or "none" (nil) where the setting has one; the server says the same.
        if (len < 1) {
            if (s.offWhenEmpty) return { value: false };
            return s.nullable ? { value: null } : { why: 'cannot be empty' };
        }
        if (s.maxLen && len > s.maxLen) return { why: 'is longer than ' + s.maxLen + ' characters' };
        const re = luaPattern(s.pattern);
        if (re && !re.test(t)) return { why: s.patternWhy || 'has characters it cannot have' };
        // Names it may not be, with the reason (DependentResources' whip_core); the server says the same.
        if (s.forbidden && Object.prototype.hasOwnProperty.call(s.forbidden, t)) {
            return { why: 'cannot be "' + t + '": ' + s.forbidden[t] };
        }
        return { value: t };
    }
    if (s.type === 'bool') {
        // A row's field left out stays out (nil), rather than becoming an explicit "off".
        if ((raw === null || raw === undefined) && s.nullable) return { value: null };
        return { value: raw === true };
    }
    if (s.type === 'enum') {
        if ((raw === null || raw === undefined || raw === '') && s.nullable) return { value: null };
        // A select hands back text; the choice's own value may not be ("the game's own" is false).
        const o = (s.options || []).find((x) => String(x.value) === String(raw));
        return o ? { value: o.value } : { why: 'is not one of the choices' };
    }
    // The character screen's shots: the shape only. Each shot is checked all the way down by the server.
    if (s.type === 'heroShots') {
        if (!Array.isArray(raw) || raw.length < 1) return { why: 'needs at least one shot' };
        if (!raw[0]) return { why: 'needs shot 1: a place with no shot of its own falls back to one' };
        if (s.maxItems && raw.length > s.maxItems) return { why: 'may have at most ' + s.maxItems + ' shots' };
        return { value: raw };
    }
    if (s.type === 'records') {
        const rows = Array.isArray(raw) ? raw : [];
        if (rows.length < (s.minItems || 0)) return { why: 'needs at least ' + s.minItems + ' rows' };
        if (s.maxItems && rows.length > s.maxItems) return { why: 'may have at most ' + s.maxItems + ' rows' };
        const out = [];
        const seen = new Map();
        for (let i = 0; i < rows.length; i++) {
            const c = checkRecord(s.fields || [], rows[i], 'row ' + (i + 1));
            if (c.why) return c;
            if (s.unique) {
                const u = getField(c.value, s.unique);
                if (u !== undefined && u !== null) {
                    if (seen.has(String(u))) return { why: 'rows ' + seen.get(String(u)) + ' and ' + (i + 1) + ' have the same ' + u };
                    seen.set(String(u), i + 1);
                }
            }
            out.push(c.value);
        }
        return { value: out };
    }
    if (s.type === 'map') {
        // raw: the drafted rows, [{ key, value }], or an object as the server sent it.
        const rows = Array.isArray(raw) ? raw : Object.entries(raw || {}).map(([key, value]) => ({ key, value }));
        if (s.maxItems && rows.length > s.maxItems) return { why: 'may have at most ' + s.maxItems + ' rows' };
        const out = {};
        for (let i = 0; i < rows.length; i++) {
            let key = String(rows[i].key === undefined || rows[i].key === null ? '' : rows[i].key).trim();
            if (!key) return { why: 'row ' + (i + 1) + ' needs a ' + (s.keyLabel || 'name').toLowerCase() };
            if (s.keyKind === 'hash') {
                if (!/^-?\d+$/.test(key) && !/^[A-Za-z0-9_]+$/.test(key)) return { why: '"' + key + '" is not a model name' };
            } else if (s.keyKind === 'number' && /^-?\d+$/.test(key)) {
                // Kept as a whole number by the server, so '007' is 7 here too.
                const n = Number(key);
                if (!Number.isSafeInteger(n)) return { why: '"' + key + '" is too big a number' };
                key = String(n);
            } else {
                const re = luaPattern(s.keyPattern);
                if (re && !re.test(key)) return { why: '"' + key + '" ' + (s.keyWhy || 'is not a name it can have') };
            }
            if (Object.prototype.hasOwnProperty.call(out, key)) return { why: '"' + key + '" is there twice' };
            const c = s.fields ? checkRecord(s.fields, rows[i].value, '"' + key + '"')
                : check(s.each || { type: 'string' }, rows[i].value);
            if (c.why) return s.fields ? c : { why: '"' + key + '" ' + c.why };
            out[key] = c.value;
        }
        return { value: out };
    }
    if (isVec(s)) {
        // raw: { x: '12.5', ... } as typed in the axis boxes.
        const out = {};
        const labels = s.axisLabels || ['X', 'Y', 'Z', 'Heading'];
        const axes = axesOf(s);
        // Every box empty is "none" where the setting has one (a store with no shopkeeper), as the server takes it.
        const blank = (a) => !raw || raw[a] === undefined || raw[a] === null || String(raw[a]).trim() === '';
        if (s.nullable && axes.every(blank)) return { value: null };
        for (let i = 0; i < axes.length; i++) {
            const a = axes[i];
            const text = raw && raw[a] !== undefined && raw[a] !== null ? String(raw[a]).trim() : '';
            const n = Number(text);
            // Mid-sentence: "New character spawn heading must be …".
            const name = labels[i].toLowerCase();
            if (text === '' || !Number.isFinite(n)) return { why: name + ' must be a number' };
            const lim = s.limits && s.limits[a];
            if (lim && (n < lim[0] || n > lim[1])) {
                return { why: name + ' must be between ' + number(lim[0]) + ' and ' + number(lim[1]) };
            }
            out[a] = n;
        }
        return { value: out };
    }
    if (s.type === 'list') {
        const parts = String(raw).split(',').map((x) => x.trim()).filter((x) => x !== '');
        const min = s.minItems || 0;
        if (parts.length < min) return { why: 'needs at least ' + min + ' entr' + (min === 1 ? 'y' : 'ies') };
        if (s.maxItems && parts.length > s.maxItems) {
            return { why: 'may have at most ' + s.maxItems + ' entr' + (s.maxItems === 1 ? 'y' : 'ies') };
        }
        const out = [];
        for (let i = 0; i < parts.length; i++) {
            const c = check(s.item || { type: 'string' }, parts[i]);
            if (c.why) return { why: 'entry ' + (i + 1) + ' ' + c.why };
            out.push(c.value);
        }
        return { value: out };
    }
    return { why: 'cannot be changed here' };
}

// ---- The Stats page's gauge row (StatOrder, widget 'statOrder') ----

const STAT_NAMES = { health: 'Health', armour: 'Armour', hunger: 'Hunger', thirst: 'Thirst',
                     developer: 'Developer Access Enabled' };
const statLabel = (n) => STAT_NAMES[n] || (n.charAt(0).toUpperCase() + n.slice(1).replace(/_/g, ' '));

/** The gauges in the order the HUD would draw them: the list's first, then the rest (the server sends the
 *  choices by name). A name with no gauge now (a stopped resource's) is not drawn. */
function gaugeOrder(list, choices) {
    const left = new Map(choices.map((c) => [c.name, c]));
    const out = [];
    for (const n of list) if (left.has(n)) { out.push(left.get(n)); left.delete(n); }
    for (const c of choices) if (left.has(c.name)) out.push(c);
    return out;
}

/** A gauge's colour as the classic skin draws it, with a faint fill of the same. */
function gaugeColors(el, hex) {
    const ok = typeof hex === 'string' && /^#[0-9a-fA-F]{6}$/.test(hex);
    const h = ok ? hex : '#ffffff';
    const n = parseInt(h.slice(1), 16);
    el.style.setProperty('--gauge-color', h);
    el.style.setProperty('--gauge-haze', `rgba(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}, 0.16)`);
}

/** The same value, all the way down, whatever order a row's fields came in. */
function same(a, b) {
    if (a === b) return true;
    if (a === null || b === null || typeof a !== 'object' || typeof b !== 'object') return false;
    // An empty table is one thing in Lua: the server sends an empty map as [], the panel makes {}.
    if (Array.isArray(a) !== Array.isArray(b)) return Object.keys(a).length === 0 && Object.keys(b).length === 0;
    const ka = Object.keys(a);
    if (ka.length !== Object.keys(b).length) return false;
    for (const k of ka) {
        if (!Object.prototype.hasOwnProperty.call(b, k) || !same(a[k], b[k])) return false;
    }
    return true;
}

// The Items page (wp/items.js) draws an item's settings with the same reading, words and checks; the Player Manager's
// Current Stats names stats as the gauge row does.
export { valueOf as settingValue, describe as describeSetting, check as checkSetting, same as sameSetting, unitParts, statLabel };

export function makeSettingsSection(def) {
    const sid = def.id;
    let pages = [];
    let page = null;                 // this section's page: { owner, label, groups }
    let gone = false;                // the server answered without it: its resource has stopped
    let groupId = null;              // the group on the right, when not searching
    let arrivalCatalogue = [];       // GTA's switch scenes, for the arrival scene lists' Add scenes
    let search = '';
    const pending = new Map();       // path -> { value } | { reset: true }
    let sending = null;              // what the Apply on its way sent: path -> entry, or null
    let els = {};
    // A table setting's rows as typed (records: the rows; map: [{ key, value }]), wrong ones too,
    // so a half-typed cell survives a redraw. Gone once the edit is discarded, reset or saved.
    const drafts = new Map();

    const keyOf = (s) => s.path;

    // What is saved: the server always sends it (the saved value, or the default when none is
    // saved). It shows rather than what is in force: a change waiting for a restart is what the
    // admin set, and the badge says it is not in force yet.
    const savedOf = (s) => valueOf(s, s.saved);
    const defaultOf = (s) => valueOf(s, s.default);

    function current(s) {
        const p = pending.get(keyOf(s));
        if (p && p.reset) return defaultOf(s);
        if (p) return p.value;
        return savedOf(s);
    }

    function allSettings() {
        const out = [];
        for (const g of (page && page.groups) || []) for (const s of g.settings) out.push({ g, s });
        return out;
    }

    function matches(s) {
        if (!search) return true;
        const q = search.toLowerCase();
        return (s.label || '').toLowerCase().includes(q) || (s.path || '').toLowerCase().includes(q)
            || (s.help || '').toLowerCase().includes(q) || (s.formLabel || '').toLowerCase().includes(q);
    }

    // ---- the list of groups ----

    function renderList() {
        els.list.innerHTML = '';
        if (!page) return;
        for (const g of page.groups) {
            const shown = g.settings.filter(matches);
            if (search && shown.length === 0) continue;
            // What is saved, against the default.
            const changed = g.settings.filter((s) => !same(savedOf(s), defaultOf(s))).length;
            const edits = g.settings.filter((s) => pending.has(keyOf(s))).length;
            const item = WP.listItem({
                title: g.label,
                sub: search ? shown.length + ' match' + (shown.length === 1 ? '' : 'es')
                    : g.settings.length + ' setting' + (g.settings.length === 1 ? '' : 's')
                        + (changed ? ' · ' + changed + ' changed' : ''),
                // Amber, waiting to be sent: blue is the picked row's own colour.
                pill: edits ? edits + ' unsaved' : null,
                pillClass: 'wp-pill-warn',
                id: g.id,
                action: 'cfgGroup',
            });
            if (!search && g.id === groupId) item.classList.add('active');
            els.list.appendChild(item);
        }
    }

    // ---- a table setting: rows of fields (records), or rows by name (map) ----

    function draftOf(s) {
        if (!drafts.has(s.path)) {
            const v = current(s);
            let rows;
            if (s.type === 'map') {
                rows = Object.entries(v && typeof v === 'object' ? v : {}).map(([key, value]) => ({ key, value: copyOf(value) }));
            } else {
                rows = copyOf(Array.isArray(v) ? v : []);
            }
            drafts.set(s.path, rows);
        }
        return drafts.get(s.path);
    }

    /** The columns: a map of single values has one, its `each`. */
    const columnsOf = (s) => s.fields || [Object.assign({ key: '', label: 'Value' }, s.each || { type: 'string' })];

    function cellValue(s, row, f) {
        const holder = s.type === 'map' ? row.value : row;
        if (!f.key) return holder;
        return getField(holder, f.key);
    }

    function cell(s, f, i, v) {
        const tag = (el) => {
            el.dataset.path = s.path;
            el.dataset.row = i;
            el.dataset.field = f.key || '__value';
            return el;
        };
        if (f.type === 'bool') {
            const box = tag(WP.el('input', 'cfg-check'));
            box.type = 'checkbox';
            box.checked = v === true;
            box.dataset.change = 'cfgCell';
            return box;
        }
        if (f.type === 'enum') {
            const opts = (f.options || []).map((o) => ({ value: o.value, label: o.label || String(o.value) }));
            if (f.nullable) opts.unshift({ value: '', label: f.emptyLabel || '—' });
            const sel = tag(WP.select(opts, { changeAction: 'cfgCell' }));
            sel.value = v === null || v === undefined ? '' : String(v);
            return sel;
        }
        if (f.type === 'vec3' || f.type === 'vec4') {
            const box = WP.el('div', 'cfg-cell-vec');
            for (const a of axesOf(f)) {
                const input = tag(WP.input({ type: 'number', value: v && v[a] !== undefined ? v[a] : '', inputAction: 'cfgCell', placeholder: a }));
                input.step = 'any';
                input.dataset.axis = a;
                input.classList.add('cfg-cell-input', 'cfg-cell-axis');
                box.appendChild(input);
            }
            if (f.here) {
                const here = tag(WP.btn('Here', 'cfgCellHere', 'ghost', s.path));
                here.classList.add('wp-btn-sm');
                box.appendChild(here);
            }
            // Placed in the world (tools/place_point.lua): a ghost to aim and move, Place to take it.
            if (f.place) {
                const place = tag(WP.btn('Place', 'cfgCellPlace', 'ghost', s.path));
                place.classList.add('wp-btn-sm');
                box.appendChild(place);
            }
            return box;
        }
        const num = f.type === 'int' || f.type === 'number';
        const input = tag(WP.input({
            type: num ? 'number' : 'text',
            value: v === null || v === undefined || v === false ? '' : v,
            inputAction: 'cfgCell',
            placeholder: f.emptyLabel || (f.offWhenEmpty ? 'off' : f.nullable ? 'none' : ''),
        }));
        input.classList.add('cfg-cell-input');
        if (num) { input.step = f.step || (f.type === 'int' ? 1 : 'any'); input.classList.add('cfg-cell-num'); }
        return input;
    }

    function tableEditor(s) {
        const rows = draftOf(s);
        const cols = columnsOf(s);
        const wrap = WP.el('div', 'cfg-table-wrap');
        const table = WP.el('table', 'cfg-table');
        const head = WP.el('tr');
        if (s.type === 'map') head.appendChild(WP.el('th', null, s.keyLabel || 'Name'));
        for (const f of cols) head.appendChild(WP.el('th', null, (f.label || f.key) + (f.unit ? ' (' + f.unit + ')' : '')));
        head.appendChild(WP.el('th'));
        table.appendChild(head);
        rows.forEach((r, i) => {
            const tr = WP.el('tr');
            tr.dataset.row = i;
            if (s.type === 'map') {
                const td = WP.el('td');
                const key = WP.input({ value: r.key === undefined || r.key === null ? '' : r.key, inputAction: 'cfgCell',
                    placeholder: s.keyKind === 'hash' ? 'model name or number' : s.keyKind === 'number' ? 'number' : 'name' });
                key.dataset.path = s.path;
                key.dataset.row = i;
                key.dataset.field = '__key';
                key.classList.add('cfg-cell-input', 'cfg-cell-key');
                td.appendChild(key);
                tr.appendChild(td);
            }
            for (const f of cols) {
                const td = WP.el('td');
                td.appendChild(cell(s, f, i, cellValue(s, r, f)));
                tr.appendChild(td);
            }
            const td = WP.el('td', 'cfg-cell-end');
            // Not offered where it would break the table's row limits (a price list keeps config.lua's rows).
            if (rows.length > (s.minItems || 0)) {
                const del = WP.btn('Remove', 'cfgRowDel', 'ghost', s.path);
                del.dataset.row = i;
                del.classList.add('wp-btn-sm');
                td.appendChild(del);
            }
            tr.appendChild(td);
            table.appendChild(tr);
        });
        wrap.appendChild(table);
        if (rows.length === 0) wrap.appendChild(WP.el('div', 'cfg-table-empty', 'No rows.'));
        if (!s.maxItems || rows.length < s.maxItems) {
            const add = WP.btn('Add a row', 'cfgRowAdd', 'ghost', s.path);
            add.classList.add('wp-btn-sm');
            wrap.appendChild(add);
        }
        return wrap;
    }

    /** The drafted rows checked: recorded when allowed, the reason shown when not. */
    function draftChanged(s) {
        const c = check(s, draftOf(s));
        if (c.why) {
            showRowError(s.path, s.label + ' ' + c.why);
            pending.delete(keyOf(s));
        } else {
            showRowError(s.path, null);
            setPending(s, c.value);
        }
        const r = els.detail.querySelector('.cfg-row[data-path="' + CSS.escape(s.path) + '"]');
        if (r) r.classList.toggle('cfg-row-edited', pending.has(keyOf(s)));
        renderList();
        renderBar();
    }

    // ---- the gauge row: the HUD's capsule, drawn small, its gauges dragged into order ----

    function statOrderEditor(s) {
        const list = Array.isArray(current(s)) ? current(s) : [];
        const choices = Array.isArray(s.choices) ? s.choices : [];
        const strip = WP.el('div', 'cfg-gauges');
        if (choices.length === 0) {
            strip.appendChild(WP.el('span', 'cfg-table-empty', 'No gauges to place.'));
            return strip;
        }
        const NS = 'http://www.w3.org/2000/svg';
        for (const c of gaugeOrder(list, choices)) {
            // A data-action of its own so the controller's circle rings it; the drag is the mouse listener below.
            const g = WP.el('div', 'cfg-gauge' + (c.off ? ' cfg-gauge-off' : ''));
            g.dataset.stat = c.name;
            g.dataset.action = 'cfgGauge';
            gaugeColors(g, c.color);
            const disc = WP.el('div', 'cfg-gauge-disc');
            const svg = document.createElementNS(NS, 'svg');
            svg.setAttribute('viewBox', '0 0 24 24');
            const path = document.createElementNS(NS, 'path');
            path.setAttribute('fill', 'currentColor');
            path.setAttribute('d', typeof c.icon === 'string' ? c.icon : '');
            svg.appendChild(path);
            disc.appendChild(svg);
            g.appendChild(disc);
            g.appendChild(WP.el('span', 'cfg-gauge-name', statLabel(c.name)));
            if (c.off) g.appendChild(WP.el('span', 'cfg-gauge-tag', 'Off'));
            g.addEventListener('mousedown', (e) => dragGauge(s, strip, g, e));
            strip.appendChild(g);
        }
        return strip;
    }

    /** Hold a gauge and move along the row: it takes the place the pointer is over, live, and the order is
     *  recorded on release. Mouse events, not pointer ones: the controller's circle sends those. */
    function dragGauge(s, strip, g, e) {
        if (e.button !== 0) return;
        e.preventDefault();
        const startX = e.clientX;
        let moved = false;
        g.classList.add('cfg-gauge-held');
        const move = (ev) => {
            if (!moved && Math.abs(ev.clientX - startX) < 4) return;
            moved = true;
            g.classList.add('cfg-gauge-drag');
            // Before the first other gauge whose middle is right of the pointer; past them all, last. In screen
            // pixels, as clientX is (the panel is zoomed, and CEF 103 measures boxes unzoomed: screenRect).
            let before = null;
            for (const o of strip.querySelectorAll('.cfg-gauge')) {
                if (o === g) continue;
                const r = screenRect(o);
                if (ev.clientX < r.left + r.width / 2) { before = o; break; }
            }
            if (before) { if (g.nextSibling !== before) strip.insertBefore(g, before); }
            else if (strip.lastChild !== g) strip.appendChild(g);
        };
        const up = () => {
            document.removeEventListener('mousemove', move, true);
            document.removeEventListener('mouseup', up, true);
            g.classList.remove('cfg-gauge-held', 'cfg-gauge-drag');
            if (!moved) return;
            const order = [...strip.querySelectorAll('.cfg-gauge')].map((x) => x.dataset.stat);
            // A name saved with no gauge now (its resource stopped) keeps a place, after these.
            for (const n of (Array.isArray(current(s)) ? current(s) : [])) if (!order.includes(n)) order.push(n);
            const c = check(s, order.join(','));
            if (c.why) { showRowError(s.path, s.label + ' ' + c.why); return; }
            setPending(s, c.value);
            renderAll();
        };
        document.addEventListener('mousemove', move, true);
        document.addEventListener('mouseup', up, true);
    }

    // ---- the hero shots: a card per character place, each made in the world ----

    /** The shots as edits will leave them, and how many places there are (Characters per account, edits too). */
    function heroState(s) {
        const list = Array.isArray(current(s)) ? copyOf(current(s)) : [];
        const mc = settingAt('MaxCharacters');
        const places = Math.max(1, Math.min(s.maxItems || 30, Number(mc ? current(mc) : list.length) || list.length || 1));
        return { list, places };
    }

    /** The shot a place shows: its own, or one that exists, in turn (client/charselect.lua's shotFor). */
    function heroShown(list, n) {
        if (list[n - 1]) return n;
        const made = [];
        list.forEach((x, i) => { if (x) made.push(i + 1); });
        return made.length ? made[(n - 1) % made.length] : null;
    }

    function heroSummary(shot) {
        const bits = [];
        if (shot.emote) bits.push('/e ' + shot.emote);
        else if (shot.anim && shot.anim.dict) bits.push('animation');
        else if (shot.scenario) bits.push(shot.scenario);
        else bits.push('standing');
        const look = shot.look;
        if (look) {
            const hh = String(look.hour == null ? 12 : look.hour).padStart(2, '0');
            const mm = String(look.minute == null ? 0 : look.minute).padStart(2, '0');
            bits.push(hh + ':' + mm + (look.weather ? ' ' + look.weather : ''));
        }
        const n = Array.isArray(shot.props) ? shot.props.length : 0;
        bits.push(n + ' prop' + (n === 1 ? '' : 's'));
        return bits.join(' · ');
    }

    /** Change place n's shot (fn edits a copy of it, or returns the new one) and record it as an edit. */
    function heroChange(s, n, fn) {
        const { list } = heroState(s);
        while (list.length < n) list.push(false);
        const next = fn(list[n - 1] ? copyOf(list[n - 1]) : null);
        list[n - 1] = next === undefined ? list[n - 1] : next;
        // Places past the last made shot hold nothing: the list ends at the last one made.
        while (list.length > 1 && !list[list.length - 1]) list.pop();
        const c = check(s, list);
        if (c.why) { showRowError(s.path, s.label + ' ' + c.why); return; }
        setPending(s, c.value);
        renderAll();
    }

    function heroShotsEditor(s) {
        const { list, places } = heroState(s);
        const box = WP.el('div', 'cfg-heroes');
        const weathers = (() => {
            const w = settingAt('WeatherTypes');
            const v = w ? current(w) : null;
            return Array.isArray(v) ? v : [];
        })();
        for (let n = 1; n <= places; n++) {
            const shot = list[n - 1] || null;
            const card = WP.el('div', 'cfg-hero' + (shot ? '' : ' cfg-hero-unset'));
            const head = WP.el('div', 'cfg-hero-head');
            head.appendChild(WP.el('span', 'cfg-hero-title', 'Hero shot ' + n));
            const shown = heroShown(list, n);
            head.appendChild(WP.el('span', 'cfg-hero-sum', shot ? heroSummary(shot)
                : (shown ? 'Not made yet: shows hero shot ' + shown : 'Not made yet')));
            head.appendChild(WP.el('span', 'cfg-spacer'));
            const edit = WP.btn(shot ? 'Edit in world' : 'Make in world', 'cfgHeroEdit', 'primary', s.path);
            edit.dataset.index = n;
            edit.classList.add('wp-btn-sm');
            head.appendChild(edit);
            if (shot && n > 1) {
                const clear = WP.btn('Clear', 'cfgHeroClear', 'ghost', s.path);
                clear.dataset.index = n;
                clear.classList.add('wp-btn-sm');
                head.appendChild(clear);
            }
            card.appendChild(head);

            if (shot) {
                // The pose and the sky are typed here; the place, camera and props are made in the world.
                const fields = WP.el('div', 'cfg-hero-fields');
                const field = (label, el) => {
                    const f = WP.el('label', 'cfg-axis');
                    f.appendChild(WP.el('span', 'cfg-axis-label', label));
                    f.appendChild(el);
                    fields.appendChild(f);
                };
                const emote = WP.input({ value: shot.emote || '', placeholder: shot.anim ? 'its animation' : 'none' });
                emote.classList.add('cfg-cell-input');
                emote.addEventListener('change', () => heroChange(s, n, (x) => {
                    const t = emote.value.trim();
                    if (t) x.emote = t; else delete x.emote;
                    return x;
                }));
                field('Emote (after /e)', emote);

                const look = shot.look || {};
                const opts = [{ value: '', label: 'as the server has it' }].concat(weathers.map((w) => ({ value: w, label: w })));
                if (look.weather && !weathers.includes(look.weather)) opts.push({ value: look.weather, label: look.weather + ' (not in the list)' });
                const sky = WP.select(opts, {});
                sky.value = look.weather || '';
                sky.addEventListener('change', () => heroChange(s, n, (x) => {
                    if (sky.value) {
                        x.look = Object.assign({ hour: 12, minute: 0, frozen: true, priority: 1000 }, x.look || {}, { weather: sky.value });
                    } else if (x.look) {
                        delete x.look.weather;
                    }
                    return x;
                }));
                field('Weather', sky);

                const clock = (key, max) => {
                    const i = WP.input({ type: 'number', value: look[key] == null ? (key === 'hour' ? 12 : 0) : look[key] });
                    i.min = 0; i.max = max; i.step = 1;
                    i.classList.add('cfg-cell-input', 'cfg-cell-num');
                    i.addEventListener('change', () => {
                        const v = Math.max(0, Math.min(max, Math.round(Number(i.value) || 0)));
                        heroChange(s, n, (x) => {
                            x.look = Object.assign({ hour: 12, minute: 0, frozen: true, priority: 1000 }, x.look || {});
                            x.look[key] = v;
                            return x;
                        });
                    });
                    return i;
                };
                field('Hour', clock('hour', 23));
                field('Minute', clock('minute', 59));
                card.appendChild(fields);
            }
            box.appendChild(card);
        }
        return box;
    }

    // ---- the arrival scenes: one list's scene lines, picked from GTA's own (client/arrival_list.lua) ----

    // The lists played at a vehicle, whose lines may be lined up with it (vehicleClip).
    const ARRIVAL_AT_VEHICLE = { inVehicle: true, onBike: true, nearCar: true };
    const sceneKey = (x) => x.dict + '/' + x.clip;

    function arrivalLines(s) { return Array.isArray(current(s)) ? copyOf(current(s)) : []; }

    function arrivalChange(s, lines) {
        const c = check(s, lines);
        if (c.why) { showRowError(s.path, s.label + ' ' + c.why); return; }
        setPending(s, c.value);
        renderAll();
    }

    /** Change line i (fn edits a copy of it) and record the list as an edit. A field set to null is left out. */
    function arrivalEdit(s, i, fn) {
        const lines = arrivalLines(s);
        if (!lines[i]) return;
        const line = fn(Object.assign({}, lines[i]));
        for (const k of Object.keys(line)) if (line[k] === null || line[k] === undefined) delete line[k];
        lines[i] = line;
        arrivalChange(s, lines);
    }

    function smallBtn(label, kind, onClick) {
        const b = WP.el('button', 'wp-btn wp-btn-sm' + (kind ? ' wp-btn-' + kind : ''), label);
        b.type = 'button';
        b.addEventListener('click', onClick);
        return b;
    }

    /** One line: what it is, Watch and Remove, and its own options. */
    function arrivalLine(s, list, line, i, e) {
        const card = WP.el('div', 'cfg-hero');
        const head = WP.el('div', 'cfg-hero-head');
        head.appendChild(WP.el('span', 'cfg-hero-title', e ? e.label : line.clip));
        const bits = [];
        if (e) bits.push(e.who);
        if (e && e.car) bits.push('made with a car');
        if (e && e.others) bits.push('made with other people');
        if (!line.cam) bits.push('no camera move');
        if (!e) bits.push(line.dict);
        head.appendChild(WP.el('span', 'cfg-hero-sum', bits.join(' · ')));
        head.appendChild(WP.el('span', 'cfg-spacer'));
        head.appendChild(smallBtn('Watch', 'primary', () => nuiCallback('cfgArrivalWatch', { line: copyOf(line) })));
        head.appendChild(smallBtn('Remove', 'ghost', () => {
            const lines = arrivalLines(s);
            lines.splice(i, 1);
            arrivalChange(s, lines);
        }));
        card.appendChild(head);

        const fields = WP.el('div', 'cfg-hero-fields');
        const field = (label, el) => {
            const f = WP.el('label', 'cfg-axis');
            f.appendChild(WP.el('span', 'cfg-axis-label', label));
            f.appendChild(el);
            fields.appendChild(f);
        };
        // Where it starts and ends, as a share of the scene (kept 0-1, typed as a percentage).
        const percent = (key, min, max, empty) => {
            const v = line[key];
            const input = WP.input({ type: 'number', value: v === undefined || v === null ? '' : Math.round(v * 100), placeholder: empty });
            input.min = min; input.max = max; input.step = 5;
            input.classList.add('cfg-cell-input', 'cfg-cell-num');
            input.addEventListener('change', () => arrivalEdit(s, i, (x) => {
                const t = input.value.trim();
                x[key] = t === '' ? null : Math.max(min, Math.min(max, Math.round(Number(t) || 0))) / 100;
                return x;
            }));
            return input;
        };
        const flag = (key) => {
            const on = line[key] === true;
            const b = smallBtn(on ? 'On' : 'Off', on ? 'primary' : null, () => arrivalEdit(s, i, (x) => {
                x[key] = on ? null : true;
                return x;
            }));
            b.classList.add('cfg-toggle');
            return b;
        };
        field('Starts at %', percent('from', 0, 95, 'the start'));
        field('Ends at %', percent('to', 5, 100, 'the end'));
        if (list === 'onFoot') field('Indoors too', flag('indoors'));
        if (ARRIVAL_AT_VEHICLE[list]) {
            const vc = WP.input({ value: line.vehicleClip || '', placeholder: 'none' });
            vc.classList.add('cfg-cell-input');
            vc.addEventListener('change', () => arrivalEdit(s, i, (x) => {
                x.vehicleClip = vc.value.trim() || null;
                return x;
            }));
            field('Vehicle clip', vc);
        }
        if (list === 'inVehicle') field('Ends in the seat', flag('getsIn'));
        card.appendChild(fields);
        return card;
    }

    /** Add scenes: GTA's own, searched and ticked; the ones the list has already are shown, ticked and fixed. */
    async function arrivalAdd(s) {
        const have = new Set(arrivalLines(s).map(sceneKey));
        const picked = new Set();
        const content = WP.el('div', 'cfg-arrival-pick');
        const search = WP.input({ placeholder: 'Search the scenes: a name, Michael, Franklin, Trevor…' });
        search.classList.add('cfg-arrival-search');
        content.appendChild(search);
        const rows = WP.el('div', 'cfg-arrival-rows');
        content.appendChild(rows);
        const draw = () => {
            rows.innerHTML = '';
            const q = search.value.trim().toLowerCase();
            for (const e of arrivalCatalogue) {
                const key = sceneKey(e);
                if (q && !(e.label + ' ' + e.who + ' ' + e.dict + ' ' + e.clip).toLowerCase().includes(q)) continue;
                const row = WP.el('label', 'cfg-arrival-row' + (have.has(key) ? ' cfg-arrival-had' : ''));
                const box = WP.el('input');
                box.type = 'checkbox';
                box.checked = have.has(key) || picked.has(key);
                box.disabled = have.has(key);
                box.addEventListener('change', () => { if (box.checked) picked.add(key); else picked.delete(key); });
                row.appendChild(box);
                row.appendChild(WP.el('span', 'cfg-arrival-name', e.label));
                const bits = [e.who];
                if (e.car) bits.push('made with a car');
                if (e.others) bits.push('made with other people');
                if (have.has(key)) bits.push('in the list');
                row.appendChild(WP.el('span', 'cfg-hero-sum', bits.join(' · ')));
                rows.appendChild(row);
            }
            if (!rows.firstChild) rows.appendChild(WP.empty('No scene matches that'));
        };
        search.addEventListener('input', draw);
        draw();
        const ok = await WP.confirm({ title: 'Add scenes to ' + (s.label || 'the list'), content, wide: true,
            confirmLabel: 'Add', canConfirm: () => picked.size > 0 });
        if (!ok || !picked.size) return;
        const lines = arrivalLines(s);
        for (const e of arrivalCatalogue) {
            if (!picked.has(sceneKey(e))) continue;
            const line = { dict: e.dict, clip: e.clip };
            if (e.cam) line.cam = e.cam;
            lines.push(line);
        }
        arrivalChange(s, lines);
    }

    function arrivalScenesEditor(s) {
        const list = s.path.split('.').pop();
        const lines = arrivalLines(s);
        const byKey = new Map(arrivalCatalogue.map((e) => [sceneKey(e), e]));
        const box = WP.el('div', 'cfg-heroes');
        const head = WP.el('div', 'cfg-hero-head');
        head.appendChild(WP.el('span', 'cfg-hero-sum', lines.length
            ? lines.length + ' scene' + (lines.length === 1 ? '' : 's')
            : 'No scenes: the picture just comes back'));
        head.appendChild(WP.el('span', 'cfg-spacer'));
        const add = smallBtn('Add scenes', 'primary', () => arrivalAdd(s));
        add.disabled = !arrivalCatalogue.length;
        head.appendChild(add);
        box.appendChild(head);
        lines.forEach((line, i) => box.appendChild(arrivalLine(s, list, line, i, byKey.get(sceneKey(line)))));
        return box;
    }

    // ---- map points: a list of places, each a position and a name, shown and edited on the map ----
    //
    // A records setting with widget 'mapPoints' (the fuel stations' icons): the rows as icons on a small map, and Edit
    // on the map opens it big over the panel, where an icon is dragged to move it, clicked to rename or remove it, and
    // added where the admin stands or in the middle of the map. `marker = { sprite, colour, name }`: the icon (GTA's
    // blip and blip colour) and a new row's name. Every change is an unsaved edit, sent by Apply.

    /** A row's position field (its first vec3) and name field (its first string). */
    function pointFields(s) {
        const fields = s.fields || [];
        return { pos: fields.find((f) => isVec(f)), name: fields.find((f) => f.type === 'string') };
    }

    const pointRows = (s) => (Array.isArray(current(s)) ? copyOf(current(s)) : []);

    function pointMark(s, row, id) {
        const { pos, name } = pointFields(s);
        const m = s.marker || {};
        const p = (pos && getField(row, pos.key)) || {};
        return { id, x: Number(p.x) || 0, y: Number(p.y) || 0,
            name: (name && getField(row, name.key)) || m.name || '',
            sprite: Number(m.sprite) || 1,
            colour: (BLIP_COLOURS.find((c) => c[0] === Number(m.colour)) || [0, '', '#ffffff'])[2] };
    }

    function mapPointsEditor(s) {
        const rows = pointRows(s);
        const box = WP.el('div', 'cfg-heroes cfg-points');
        box.appendChild(WP.el('span', 'cfg-hero-sum', rows.length
            ? rows.length + ' on the map'
            : 'None yet: Edit on the map adds them'));
        box.appendChild(WP.place({
            name: s.label, marks: rows.map((r, i) => pointMark(s, r, i + 1)),
            openLabel: 'Edit on the map', onOpen: () => mapPointsEdit(s),
        }));
        return box;
    }

    /** The big map, the rows on it to move, rename, add and remove. */
    function mapPointsEdit(s) {
        const { pos, name } = pointFields(s);
        if (!pos) return;
        const m = s.marker || {};
        const r2 = (n) => Math.round(n * 100) / 100;
        // The rows as edited here, each with an id of its own while the map is up.
        let serial = 0;
        const list = pointRows(s).map((row) => ({ id: ++serial, row }));
        const marks = () => list.map((it) => pointMark(s, it.row, it.id));
        let area = null;
        let said = null;   // the card's message line, while one is up

        /** The rows as they stand here, checked, as the unsaved edit; the reason when they cannot be. */
        const record = () => {
            const c = check(s, list.map((it) => it.row));
            if (c.why) {
                if (said) said.textContent = s.label + ' ' + c.why;
                return false;
            }
            setPending(s, c.value);
            renderList();
            renderBar();
            area.update(marks());
            return true;
        };

        // A place's height: the one given (where the admin stands), else the ground's there (the 3D map's), else the
        // height it had (no 3D map), else 0.
        const at = (x, y, z, had) => {
            const ground = area.map.groundAt(x, y);
            const h = typeof z === 'number' ? z : ground !== null ? ground : had && typeof had.z === 'number' ? had.z : 0;
            return { x: r2(x), y: r2(y), z: r2(h) };
        };

        const add = (x, y, z) => {
            if (s.maxItems && list.length >= s.maxItems) return;
            const row = {};
            setField(row, pos.key, at(x, y, z));
            if (name) setField(row, name.key, m.name || 'New place');
            const it = { id: ++serial, row };
            list.push(it);
            if (record()) area.pick(it.id);
            else list.pop();
        };

        const card = (mark) => {
            const it = list.find((x) => x.id === mark.id);
            if (!it) return null;
            const body = WP.el('div', 'cfg-point-card');
            if (name) {
                const input = WP.input({ value: getField(it.row, name.key) || '' });
                input.addEventListener('change', () => {
                    const was = getField(it.row, name.key);
                    setField(it.row, name.key, input.value.trim() || null);
                    if (!record()) setField(it.row, name.key, was);
                });
                body.appendChild(WP.field(name.label || 'Name', input, true));
            }
            body.appendChild(WP.el('span', 'wp-hint', 'Drag the icon to move it.'));
            body.appendChild(smallBtn('Remove', 'danger', () => {
                const i = list.indexOf(it);
                if (i < 0) return;
                list.splice(i, 1);
                if (!record()) list.splice(i, 0, it);
            }));
            said = WP.el('div', 'wp-field-msg');
            body.appendChild(said);
            return body;
        };

        area = WP.openPlace({
            name: s.label,
            hint: 'Drag an icon to move it, click one to rename or remove it. Apply saves the changes.',
            marks: marks(), card,
            onMove: (mark, x, y) => {
                const it = list.find((i) => i.id === mark.id);
                if (!it) return;
                const was = getField(it.row, pos.key);
                setField(it.row, pos.key, at(x, y, null, was));
                if (!record()) { setField(it.row, pos.key, was); area.update(marks()); }
            },
            actions: [
                { label: 'Add where I stand', onClick: () => nuiCallback('cfgHere', {}).then((p) => {
                    if (p && typeof p.x === 'number') add(p.x, p.y, p.z);
                }) },
                { label: 'Add in the middle', onClick: (a) => {
                    const w = a.map.worldAt(...a.map.middle());
                    if (w) add(w[0], w[1]);
                } },
            ],
            closeLabel: 'Done',
            onClose: () => renderDetail(),
        });
    }

    // ---- one setting ----

    function editor(s) {
        const v = current(s);
        if (s.widget === 'statOrder') return statOrderEditor(s);
        if (s.widget === 'heroShots') return heroShotsEditor(s);
        if (s.widget === 'arrivalScenes') return arrivalScenesEditor(s);
        if (s.widget === 'mapPoints' && pointFields(s).pos) return mapPointsEditor(s);
        if (s.type === 'records' || s.type === 'map') return tableEditor(s);
        if (s.type === 'bool') {
            const b = WP.btn(v ? 'On' : 'Off', 'cfgToggle', v ? 'primary' : null, s.path);
            b.classList.add('cfg-toggle');
            return b;
        }
        if (s.type === 'enum') {
            const sel = WP.select((s.options || []).map((o) => ({ value: o.value, label: o.label || String(o.value) })),
                { changeAction: 'cfgEdit' });
            sel.value = String(v);
            sel.dataset.path = s.path;
            return sel;
        }
        // A name chosen from another setting's list as it stands here, unsaved edits included (a
        // scene's weather from the weather list). A name no longer on it stays shown, and says so.
        if (s.type === 'string' && s.choicesFrom) {
            const from = settingAt(s.choicesFrom);
            const list = from ? current(from) : null;
            const opts = (Array.isArray(list) ? list : []).map((x) => ({ value: String(x), label: String(x) }));
            if (v !== null && v !== undefined && !opts.some((o) => o.value === String(v))) {
                opts.unshift({ value: String(v), label: v + ' (not in the list)' });
            }
            if (s.nullable) opts.unshift({ value: '', label: s.emptyLabel || 'none' });
            const sel = WP.select(opts, { changeAction: 'cfgEdit' });
            sel.value = v === null || v === undefined ? '' : String(v);
            sel.dataset.path = s.path;
            return sel;
        }
        if (isVec(s)) {
            // One box per axis, named; "Use where I stand" fills them from the admin's own spot.
            const box = WP.el('div', 'cfg-vec');
            const labels = s.axisLabels || ['X', 'Y', 'Z', 'Heading'];
            axesOf(s).forEach((a, i) => {
                const input = WP.input({ type: 'number', value: v && v[a] !== undefined ? v[a] : '', inputAction: 'cfgVec' });
                input.step = 'any';
                input.dataset.path = s.path;
                input.dataset.axis = a;
                input.classList.add('cfg-input-num', 'cfg-input-axis');
                const f = WP.el('label', 'cfg-axis');
                f.appendChild(WP.el('span', 'cfg-axis-label', labels[i]));
                f.appendChild(input);
                box.appendChild(f);
            });
            if (s.here) {
                const here = WP.btn('Use where I stand', 'cfgHere', 'ghost', s.path);
                here.classList.add('wp-btn-sm');
                box.appendChild(here);
            }
            // Placed in the world (tools/place_point.lua): a ghost to aim and move, Place to take it.
            if (s.place) {
                const place = WP.btn('Place in the world', 'cfgPlacePoint', 'ghost', s.path);
                place.classList.add('wp-btn-sm');
                box.appendChild(place);
            }
            // A shot's camera: flown into place (Enter takes it), or the camera the admin looks through now.
            if (s.camera) {
                const place = WP.btn('Place camera', 'cfgPlace', 'primary', s.path);
                place.classList.add('wp-btn-sm');
                box.appendChild(place);
                const cam = WP.btn('Use my camera', 'cfgCamera', 'ghost', s.path);
                cam.classList.add('wp-btn-sm');
                box.appendChild(cam);
            }
            return box;
        }
        let shown = v === null || v === undefined || v === false ? '' : v;
        if (s.type === 'list') shown = listText(v);
        let placeholder;
        if (s.emptyLabel) placeholder = s.emptyLabel;
        else if (s.offWhenEmpty) placeholder = 'off';
        else if (s.nullable) placeholder = 'none';
        else if (s.type === 'list') placeholder = 'entries, split by commas';
        const input = WP.input({
            type: (s.type === 'int' || s.type === 'number') ? 'number' : 'text',
            value: shown,
            inputAction: 'cfgEdit',
            placeholder,
        });
        input.dataset.path = s.path;
        if (s.type === 'list' || s.type === 'string') input.classList.add('cfg-input-text');
        if (s.type === 'int' || s.type === 'number') {
            if (s.min !== undefined && s.min !== null) input.min = s.min;
            if (s.max !== undefined && s.max !== null) input.max = s.max;
            input.step = s.step || (s.type === 'int' ? 1 : 'any');
            input.classList.add('cfg-input-num');
        }
        // No maxLength: the browser counts UTF-16 units, the server characters. check() says when
        // text is too long, counted the server's way.
        return input;
    }

    /** One setting's row. `compact`: a field inside a form card (an item's weight): no path, no
     *  help, no "changed by" — the card says those once. */
    function row(s, compact) {
        const r = WP.el('div', compact ? 'cfg-row cfg-row-compact' : 'cfg-row');
        r.dataset.path = s.path;
        const edited = pending.has(keyOf(s));
        if (edited) r.classList.add('cfg-row-edited');

        const head = WP.el('div', 'cfg-row-head');
        head.appendChild(WP.el('span', 'cfg-row-label', s.label || s.path));
        // (No dot for a setting changed from its default: Josh, 11 Nov, off. The group's list says how many are,
        // and the row has its Reset.)
        const isChanged = !same(current(s), defaultOf(s));
        if (!compact) head.appendChild(WP.el('span', 'cfg-row-path', s.path));
        const spacer = WP.el('span', 'cfg-spacer');
        head.appendChild(spacer);
        if (s.waiting && !edited) {
            head.appendChild(WP.el('span', 'wp-pill wp-pill-warn', 'Waiting for restart'));
        } else if (s.apply === 'restart') {
            head.appendChild(WP.el('span', 'wp-pill cfg-pill-dim', 'Next restart'));
        } else if (s.apply === 'readonly') {
            head.appendChild(WP.el('span', 'wp-pill cfg-pill-dim', 'Fixed'));
        }
        r.appendChild(head);

        if (s.help && !compact) r.appendChild(WP.el('div', 'wp-hint cfg-help', s.help));
        // Where the real lever is: a button that opens that section (garages, shops, the clock).
        const linkBtn = () => {
            const b = WP.btn(s.link.label || 'Open', 'cfgLink', 'ghost', s.link.section);
            b.classList.add('wp-btn-sm');
            return b;
        };
        // SHOWN, NEVER EDITED: what it is, and why it cannot change here.
        if (s.apply === 'readonly') {
            r.appendChild(WP.el('div', 'cfg-fixed', describe(s, savedOf(s))));
            if (s.why) r.appendChild(WP.el('div', 'cfg-why', s.why));
            if (s.link) r.appendChild(linkBtn());
            return r;
        }
        // Said on the row, not in a tooltip: the game's browser draws no tooltips.
        if (s.apply === 'restart') {
            r.appendChild(WP.el('div', 'cfg-why', 'Takes effect when ' + def.owner + ' next starts. ' + (s.why || '')));
        }

        const line = WP.el('div', 'cfg-row-edit');
        const num = s.type === 'int' || s.type === 'number';
        const u = unitParts(s);
        if (num && u.before) line.appendChild(WP.el('span', 'cfg-unit', u.before));
        line.appendChild(editor(s));
        if (num && u.after) line.appendChild(WP.el('span', 'cfg-unit', u.after));
        line.appendChild(WP.el('span', 'cfg-default', 'Default: ' + describe(s, defaultOf(s))));
        if (isChanged) {
            const reset = WP.btn('Reset', 'cfgReset', 'ghost', s.path);
            reset.classList.add('wp-btn-sm');
            line.appendChild(reset);
        }
        if (s.link) line.appendChild(linkBtn());
        r.appendChild(line);

        const err = WP.el('div', 'wp-field-msg cfg-error');
        err.style.display = 'none';
        r.appendChild(err);

        if (s.changedBy && !edited && !compact) {
            r.appendChild(WP.el('div', 'cfg-meta', 'Changed by ' + s.changedBy + (s.changedAt ? ', ' + s.changedAt : '')));
        }
        return r;
    }

    /** A row that shows only while another setting is a value (`shownWhen: { path, equals }`), as that setting is
     *  here, unsaved edits included: Map options' minimap rows, only while "Same minimap for everyone" is on. */
    function shownNow(s) {
        const w = s.shownWhen;
        if (!w || !w.path) return true;
        const dep = settingAt(w.path);
        return !dep || same(current(dep), w.equals);
    }

    /** Does a row's showing hang on this setting? (Then an edit to it redraws the rows.) */
    function hasDependants(s) {
        return allSettings().some(({ s: o }) => o.shownWhen && o.shownWhen.path === s.path);
    }

    /** Rows into `into`, the fields of one form (an item, a stat: s.form) together in one card. */
    function renderRows(list, into) {
        let grid = null;
        let form = null;
        for (const s of list) {
            if (!shownNow(s)) continue;
            if (!s.form) {
                form = null;
                into.appendChild(row(s));
                continue;
            }
            if (s.form !== form) {
                form = s.form;
                // A camera's card (its place comes first) lays its rows out one under another: a place and a turn
                // are three boxes each, too wide for the grid's columns.
                const card = WP.el('div', 'cfg-row cfg-form' + (s.camera ? ' cfg-form-camera' : ''));
                const head = WP.el('div', 'cfg-row-head');
                head.appendChild(WP.el('span', 'cfg-row-label', s.formLabel || s.form));
                head.appendChild(WP.el('span', 'cfg-row-path', s.form));
                card.appendChild(head);
                if (s.formHelp) card.appendChild(WP.el('div', 'wp-hint cfg-help', s.formHelp));
                grid = WP.el('div', 'cfg-form-grid');
                card.appendChild(grid);
                into.appendChild(card);
            }
            grid.appendChild(row(s, true));
        }
    }

    function renderDetail() {
        els.detail.innerHTML = '';
        if (!page) {
            els.detail.appendChild(WP.empty(gone
                ? def.owner + ' is not running. Its settings come back when it starts, and unsaved edits here wait for it.'
                : 'Loading settings…'));
            return;
        }
        if (search) {
            let any = false;
            for (const g of page.groups) {
                const shown = g.settings.filter(matches);
                if (shown.length === 0) continue;
                any = true;
                els.detail.appendChild(WP.el('div', 'wp-section-title', g.label));
                renderRows(shown, els.detail);
            }
            if (!any) els.detail.appendChild(WP.empty('No setting matches "' + search + '"'));
            return;
        }
        const g = page.groups.find((x) => x.id === groupId) || page.groups[0];
        if (!g) {
            els.detail.appendChild(WP.empty('No settings'));
            return;
        }
        groupId = g.id;
        els.detail.appendChild(WP.el('div', 'wp-pane-title', g.label));
        renderRows(g.settings, els.detail);
    }

    function renderBar(msg, isErr) {
        const n = pending.size;
        els.barText.textContent = msg || (sending ? 'Saving…'
            : n === 0 ? 'No unsaved changes · ' + (def.title || 'Settings saved here are applied over config.lua')
            : n + ' unsaved change' + (n === 1 ? '' : 's') + (gone ? ', waiting for ' + def.owner : ''));
        els.barText.classList.toggle('cfg-bar-err', !!isErr);
        // Locked while a save is on its way (a second Apply would send everything twice), and while
        // the page's resource is stopped (the server has nothing to save them to).
        els.apply.disabled = n === 0 || !!sending || gone;
        // Discard also throws away a table half typed (no change to send yet, but rows on screen
        // that are not what is saved). Every table drawn has a draft; only a wrong one counts.
        let halfTyped = false;
        for (const [path, rows] of drafts) {
            const ds = settingAt(path);
            if (ds && !pending.has(path) && check(ds, rows).why) { halfTyped = true; break; }
        }
        els.discard.disabled = (n === 0 && !halfTyped) || !!sending;
        els.bar.classList.toggle('cfg-bar-live', n > 0);
    }

    /** Redraw the rows, keeping the box being typed in: another admin's save redraws the page,
     *  and must not take the caret (or a half-typed value) away. */
    function renderDetailKeepingFocus() {
        const a = document.activeElement;
        const keep = a && els.detail.contains(a) && a.dataset && a.dataset.path
            ? { path: a.dataset.path, axis: a.dataset.axis, row: a.dataset.row, field: a.dataset.field,
                value: a.value, start: a.selectionStart, end: a.selectionEnd } : null;
        // A table's cell: its draft already holds what was typed, so only the caret comes back.
        if (keep && keep.row !== undefined && keep.field !== undefined) {
            renderDetail();
            let sel = '.cfg-row[data-path="' + CSS.escape(keep.path) + '"] [data-row="' + keep.row + '"][data-field="'
                + CSS.escape(keep.field) + '"]';
            if (keep.axis) sel += '[data-axis="' + keep.axis + '"]';
            const box = els.detail.querySelector(sel);
            if (box && box.focus) {
                box.focus();
                try { if (keep.start !== null) box.setSelectionRange(keep.start, keep.end); } catch (e) { /* not a text box */ }
            }
            return;
        }
        // A position's other axes, half-typed, come back too.
        const axes = {};
        if (keep && keep.axis) {
            const r = a.closest('.cfg-row');
            for (const i of r ? r.querySelectorAll('input[data-axis]') : []) axes[i.dataset.axis] = i.value;
        }
        renderDetail();
        if (!keep) return;
        const rowSel = '.cfg-row[data-path="' + CSS.escape(keep.path) + '"]';
        const box = keep.axis
            ? els.detail.querySelector(rowSel + ' input[data-axis="' + keep.axis + '"]')
            : els.detail.querySelector(rowSel + ' input, ' + rowSel + ' select');
        if (!box) return;
        if (keep.axis) {
            for (const i of els.detail.querySelectorAll(rowSel + ' input[data-axis]')) {
                if (axes[i.dataset.axis] !== undefined) i.value = axes[i.dataset.axis];
            }
        } else {
            box.value = keep.value;
        }
        box.focus();
        try { if (keep.start !== null) box.setSelectionRange(keep.start, keep.end); } catch (e) { /* not a text box */ }
        const s = settingAt(keep.path);
        if (s && box.tagName === 'INPUT') {
            const c = check(s, rawFrom(s, box));
            showRowError(s.path, c.why ? s.label + ' ' + c.why : null);
        }
    }

    function renderAll() {
        renderList();
        renderDetail();
        renderBar();
    }

    function settingAt(path) {
        for (const { s } of allSettings()) if (s.path === path) return s;
        return null;
    }

    /** What a row's boxes hold, as check() takes it: a position's axes together, else the box. */
    function rawFrom(s, box) {
        if (!isVec(s)) return box.value;
        const r = box.closest('.cfg-row');
        const raw = {};
        for (const i of r ? r.querySelectorAll('input[data-axis]') : []) raw[i.dataset.axis] = i.value;
        return raw;
    }

    /** An edit typed in a box: checked as it is typed, recorded only when it is allowed. */
    function typed(el) {
        const s = settingAt(el.dataset.path);
        if (!s) return;
        const c = check(s, rawFrom(s, el));
        if (c.why) {
            showRowError(s.path, s.label + ' ' + c.why);
            // Not recorded: Apply never sends a value the panel already knows is wrong.
            pending.delete(keyOf(s));
            renderList();
            renderBar();
            return;
        }
        showRowError(s.path, null);
        setPending(s, c.value);
        // Rows that show only for some value of this one come and go with it.
        if (hasDependants(s)) { renderDetailKeepingFocus(); renderList(); renderBar(); return; }
        // Only the list and the bar redraw while typing; redrawing the row would take the caret
        // out of the box.
        const r = el.closest('.cfg-row');
        if (r) r.classList.toggle('cfg-row-edited', pending.has(keyOf(s)));
        renderList();
        renderBar();
    }

    /** Record an edit, or drop it when it puts the value back to what is saved. */
    function setPending(s, value) {
        if (same(value, savedOf(s))) pending.delete(keyOf(s));
        else pending.set(keyOf(s), { value });
    }

    /** A camera's place, turn and zoom ({ pos, rot, fov }) into its three settings, checked, as unsaved edits. */
    function takeCamera(s, cam) {
        if (!s || !s.camera || !cam || !cam.pos || typeof cam.pos.x !== 'number') return;
        const r2 = (n) => Math.round(n * 100) / 100;
        const v3 = (v) => (v && typeof v.x === 'number' ? { x: r2(v.x), y: r2(v.y), z: r2(v.z) } : null);
        const sets = [
            [s, v3(cam.pos)],
            [settingAt(s.camera.rot), v3(cam.rot)],
            [settingAt(s.camera.fov), typeof cam.fov === 'number' ? r2(cam.fov) : null],
        ];
        const errors = [];
        for (const [t, raw] of sets) {
            if (!t || raw === null) continue;
            const c = check(t, raw);
            if (c.why) errors.push([t.path, t.label + ' ' + c.why]);
            else setPending(t, c.value);
        }
        renderAll();
        // After the redraw, which would otherwise clear them.
        for (const [path, why] of errors) showRowError(path, why);
    }

    /** A point placed in the world ({ path, row?, field?, value: { x, y, z, w } }): into a row's cell, as "Here" does,
     *  or into a position setting, as "Use where I stand" does, waiting for Apply. */
    function takePoint(d) {
        const s = settingAt(d && d.path);
        const pos = d && d.value;
        if (!s || !pos || typeof pos.x !== 'number') return;
        const r2 = (n) => Math.round(n * 100) / 100;
        if (typeof d.row === 'number' && typeof d.field === 'string') {
            const row = draftOf(s)[d.row];
            const f = columnsOf(s).find((x) => x.key === d.field);
            if (!row || !f) return;
            const v = { x: r2(pos.x), y: r2(pos.y), z: r2(pos.z) };
            if (f.type === 'vec4') v.w = r2(pos.w || 0);
            setField(s.type === 'map' ? (row.value = row.value || {}) : row, d.field, v);
            renderDetailKeepingFocus();
            draftChanged(s);
            return;
        }
        const c = check(s, { x: r2(pos.x), y: r2(pos.y), z: r2(pos.z), w: r2(pos.w || 0) });
        if (c.why) { showRowError(s.path, s.label + ' ' + c.why); return; }
        setPending(s, c.value);
        renderAll();
    }

    function showRowError(path, why) {
        const r = els.detail.querySelector('.cfg-row[data-path="' + CSS.escape(path) + '"]');
        if (!r) return;
        const e = r.querySelector('.cfg-error');
        if (!e) return;
        e.textContent = why || '';
        e.style.display = why ? '' : 'none';
    }

    WhipPanel.registerSection({
        id: sid,
        group: def.group || 'settings',
        // Read at each open: a satellite's page can come back with a new label and place.
        get label() { return def.label; },
        get order() { return def.order || 10; },
        permanentOnly: true,
        hidden: def.hidden,

        render(root) {
            els = {};
            // The shell builds the section afresh at every open, with an empty search box.
            search = '';
            // The search goes to the top of the group list (the shell's dockToolbars). What the page
            // saves over is said in the Apply bar while nothing is waiting (renderBar).
            root.appendChild(WP.toolbar({
                search: { inputAction: 'cfgSearch', placeholder: 'Search settings…', id: 'cfg-search-' + sid },
            }));
            const split = WP.el('div', 'wp-split');
            const col = WP.el('div', 'wp-list-col');
            els.list = WP.el('div', 'wp-list');
            col.appendChild(els.list);
            split.appendChild(col);
            els.detail = WP.el('div', 'wp-detail cfg-detail');
            split.appendChild(els.detail);
            root.appendChild(split);

            els.bar = WP.el('div', 'cfg-bar');
            els.barText = WP.el('span', 'cfg-bar-text', '');
            els.bar.appendChild(els.barText);
            els.bar.appendChild(WP.el('span', 'cfg-spacer'));
            els.discard = WP.btn('Discard', 'cfgDiscard', 'ghost');
            els.apply = WP.btn('Apply', 'cfgApply', 'primary');
            els.bar.appendChild(els.discard);
            els.bar.appendChild(els.apply);
            root.appendChild(els.bar);
            renderAll();
        },

        onData(kind, payload) {
            if (kind === 'all') {
                pages = (payload && payload.pages) || [];
                // GTA's switch scenes, for the arrival scene lists (whip_core's page only).
                if (payload && Array.isArray(payload.arrivalCatalogue)) arrivalCatalogue = payload.arrivalCatalogue;
                page = pages.find((p) => p.owner === def.owner) || null;
                // A satellite that stopped: nothing to check its edits against, so they are kept
                // as they are until it starts again.
                gone = !page;
                if (gone) {
                    renderList();
                    renderDetail();
                    renderBar();
                    return;
                }
                // An edit that now matches what is saved (another admin made the same change, or
                // a reset whose default is now saved) goes.
                for (const [path, p] of [...pending]) {
                    const s = settingAt(path);
                    if (!s) { pending.delete(path); continue; }
                    if (p.reset ? same(savedOf(s), defaultOf(s)) : same(p.value, savedOf(s))) pending.delete(path);
                }
                // A table drafted with nothing left to send is drawn from what is saved again; one
                // still being typed (a new row not yet whole) stays as it is.
                for (const path of [...drafts.keys()]) {
                    if (pending.has(path)) continue;
                    const ds = settingAt(path);
                    if (!ds || !check(ds, drafts.get(path)).why) drafts.delete(path);
                }
                renderList();
                renderDetailKeepingFocus();
                renderBar();
            } else if (kind === 'applied') {
                // Only what was sent is done: an edit made while the save was on its way stays.
                if (sending) {
                    for (const [path, sent] of sending) {
                        if (same(pending.get(path), sent)) { pending.delete(path); drafts.delete(path); }
                    }
                }
                sending = null;
                renderList();
                renderBar();
            } else if (kind === 'cameraPlaced') {
                // Enter in the world (Place camera): the shot flown to, as edits waiting for Apply.
                takeCamera(settingAt(payload && payload.path), payload);
            } else if (kind === 'pointPlaced') {
                // Place in the world (tools/place_point.lua): the point, as an edit waiting for Apply.
                takePoint(payload);
            } else if (kind === 'heroShotEdited') {
                // Done in the world (Edit in world): that place's shot, as an edit waiting for Apply.
                const s = settingAt('CharSelect.slots');
                const n = Number(payload && payload.index);
                if (s && n >= 1 && payload.shot && typeof payload.shot === 'object') heroChange(s, n, () => payload.shot);
            } else if (kind === 'applyFailed') {
                sending = null;
                renderBar((payload && payload.why) || 'Not saved', true);
            } else if (kind === 'error') {
                // A failed refresh keeps what is on screen, and says why in the bar.
                if (!page) {
                    els.detail.innerHTML = '';
                    els.detail.appendChild(WP.empty((payload && payload.why) || 'The settings could not be read'));
                }
                renderBar((payload && payload.why) || 'The settings could not be read', true);
            }
        },

        onEscape() {
            if (search) {
                search = '';
                const input = document.getElementById('cfg-search-' + sid);
                if (input) input.value = '';
                renderAll();
                return true;
            }
            return false;
        },

        actions: {
            cfgSearch: (el) => { search = el.value.trim(); renderList(); renderDetail(); },
            cfgGroup: (el) => { groupId = el.dataset.id; search = ''; const i = document.getElementById('cfg-search-' + sid); if (i) i.value = ''; renderAll(); },
            cfgToggle: async (el) => {
                const s = settingAt(el.dataset.arg);
                if (!s) return;
                const on = !current(s);
                // An experimental feature (warnOn) asks before it goes on; off never asks.
                if (on && s.warnOn) {
                    const ok = await WP.confirm({ title: s.warnOn.title || 'Turn it on?', body: s.warnOn.text || '',
                        confirmLabel: s.warnOn.confirm || 'Turn it on', danger: true });
                    if (!ok || current(s) === on) return;
                }
                setPending(s, on);
                renderAll();
            },
            cfgEdit: (el) => typed(el),
            cfgVec: (el) => typed(el),
            // A gauge on the Stats page's row: a click alone does nothing (the drag is dragGauge's).
            cfgGauge: () => {},
            // A hero shot made in the world, from the shot as it stands here (a place with none starts from the one
            // it shows). Done comes back as 'heroShotEdited' (onData).
            cfgHeroEdit: (el) => {
                const s = settingAt(el.dataset.arg);
                if (!s) return;
                const n = Number(el.dataset.index);
                const { list } = heroState(s);
                const shown = heroShown(list, n);
                const shot = list[n - 1] || (shown ? list[shown - 1] : null);
                if (!shot) return;
                nuiCallback('cfgHeroEdit', { section: sid, index: n, shot: copyOf(shot) });
            },
            cfgHeroClear: (el) => {
                const s = settingAt(el.dataset.arg);
                if (s) heroChange(s, Number(el.dataset.index), () => false);
            },
            // To the section where a setting's real lever is (garages, shops, the clock).
            cfgLink: (el) => { if (el.dataset.arg) WhipPanel.switchTo(el.dataset.arg); },
            // A cell of a table setting: only that field of that row changes in the draft, so the
            // fields nobody touched stay exactly as they were.
            cfgCell: (el) => {
                const s = settingAt(el.dataset.path);
                if (!s) return;
                const rows = draftOf(s);
                const row = rows[Number(el.dataset.row)];
                if (!row) return;
                const field = el.dataset.field;
                if (field === '__key') {
                    row.key = el.value;
                } else {
                    let raw;
                    if (el.type === 'checkbox') raw = el.checked;
                    else if (el.dataset.axis) {
                        raw = {};
                        for (const i of el.closest('td').querySelectorAll('input[data-axis]')) raw[i.dataset.axis] = i.value;
                    } else raw = el.value;
                    if (s.type === 'map') {
                        if (field === '__value') row.value = raw;
                        else {
                            if (!row.value || typeof row.value !== 'object') row.value = {};
                            setField(row.value, field, raw);
                        }
                    } else {
                        setField(row, field, raw);
                    }
                }
                draftChanged(s);
            },
            cfgRowAdd: (el) => {
                const s = settingAt(el.dataset.arg);
                if (!s) return;
                const rows = draftOf(s);
                rows.push(s.type === 'map' ? { key: '', value: s.fields ? {} : '' } : {});
                renderDetailKeepingFocus();
                draftChanged(s);
            },
            cfgRowDel: (el) => {
                const s = settingAt(el.dataset.arg);
                if (!s) return;
                draftOf(s).splice(Number(el.dataset.row), 1);
                renderDetailKeepingFocus();
                draftChanged(s);
            },
            // "Here" in a row's position cell: the admin's own spot, into that row only.
            cfgCellHere: (el) => {
                const s = settingAt(el.dataset.arg);
                if (!s) return;
                const i = Number(el.dataset.row);
                const field = el.dataset.field;
                nuiCallback('cfgHere', {}).then((pos) => {
                    if (!pos || typeof pos.x !== 'number') return;
                    const row = draftOf(s)[i];
                    if (!row) return;
                    const r2 = (n) => Math.round(n * 100) / 100;
                    const f = columnsOf(s).find((x) => x.key === field);
                    const v = { x: r2(pos.x), y: r2(pos.y), z: r2(pos.z) };
                    if (f && f.type === 'vec4') v.w = r2(pos.w || 0);
                    setField(s.type === 'map' ? (row.value = row.value || {}) : row, field, v);
                    renderDetailKeepingFocus();
                    draftChanged(s);
                });
            },
            // "Place" in a row's position cell, or a position's "Place in the world": the panel steps aside for a
            // ghost in the world, and Place there comes back as 'pointPlaced' (onData), Esc as nothing.
            cfgCellPlace: (el) => {
                const s = settingAt(el.dataset.arg);
                if (!s) return;
                const i = Number(el.dataset.row);
                const field = el.dataset.field;
                const f = columnsOf(s).find((x) => x.key === field);
                const row = draftOf(s)[i];
                if (!f || !row) return;
                const at = getField(s.type === 'map' ? (row.value || {}) : row, field);
                nuiCallback('cfgPlacePoint', {
                    section: sid, path: s.path, row: i, field, at: at || null,
                    place: typeof f.place === 'object' ? f.place : {}, label: f.label || s.label,
                });
            },
            cfgPlacePoint: (el) => {
                const s = settingAt(el.dataset.arg);
                if (!s || !s.place) return;
                nuiCallback('cfgPlacePoint', {
                    section: sid, path: s.path, at: current(s) || null,
                    place: typeof s.place === 'object' ? s.place : {}, label: s.label,
                });
            },
            cfgCamera: (el) => {
                const s = settingAt(el.dataset.arg);
                if (!s || !s.camera) return;
                nuiCallback('cfgCamera', {}).then((cam) => takeCamera(s, cam));
            },
            // Fly a free camera from the shot as it stands here, unsaved edits included; Enter in the world
            // comes back as 'cameraPlaced' (onData), Esc as nothing.
            cfgPlace: (el) => {
                const s = settingAt(el.dataset.arg);
                if (!s || !s.camera) return;
                const rot = settingAt(s.camera.rot), fov = settingAt(s.camera.fov);
                nuiCallback('cfgPlaceCamera', {
                    section: sid, path: s.path,
                    pos: current(s), rot: rot ? current(rot) : null, fov: fov ? current(fov) : null,
                });
            },
            cfgHere: (el) => {
                const s = settingAt(el.dataset.arg);
                if (!s) return;
                nuiCallback('cfgHere', {}).then((pos) => {
                    if (!pos || typeof pos.x !== 'number') return;
                    const r2 = (n) => Math.round(n * 100) / 100;
                    const raw = { x: r2(pos.x), y: r2(pos.y), z: r2(pos.z), w: r2(pos.w || 0) };
                    const c = check(s, raw);
                    if (c.why) { showRowError(s.path, s.label + ' ' + c.why); return; }
                    setPending(s, c.value);
                    renderAll();
                });
            },
            cfgReset: (el) => {
                const s = settingAt(el.dataset.arg);
                if (!s) return;
                // What is saved is already the default (an unsent edit made it differ): dropping
                // the edit is the reset. Otherwise the default is saved on Apply.
                if (same(savedOf(s), defaultOf(s))) pending.delete(keyOf(s));
                else pending.set(keyOf(s), { reset: true });
                drafts.delete(s.path);
                renderAll();
            },
            cfgDiscard: () => { if (sending) return; pending.clear(); drafts.clear(); renderAll(); },
            cfgApply: () => {
                if (pending.size === 0 || sending) return;
                const changes = [];
                sending = new Map();
                for (const [path, p] of pending) {
                    sending.set(path, p);
                    const s = settingAt(path);
                    if (p.reset) changes.push({ owner: def.owner, path, reset: true });
                    else if (p.value === null) changes.push({ owner: def.owner, path, isNil: true });
                    // A map goes as its rows: a plain object could not carry a model's number key.
                    else if (s && s.type === 'map') changes.push({ owner: def.owner, path, value: { pairs: Object.entries(p.value) } });
                    else changes.push({ owner: def.owner, path, value: p.value });
                }
                renderBar();
                // The section goes with it, so the answer comes back here (each page is a section).
                nuiCallback('cfgApply', { changes, section: sid });
            },
        },
    });
}

makeSettingsSection({ id: 'config', owner: 'whip_core', label: 'Config', order: 10 });

// EACH SATELLITE'S PAGE IS A SECTION OF ITS OWN, after Config, made from the list the server sends
// with the open (server/permissions.lua). One whose resource has stopped since is hidden, not
// removed: it comes back when the resource does.
const livePages = new Set();
const satelliteDefs = new Map();   // owner -> the def its section was made from (label, order kept current)
WhipPanel.addOpenHook((data) => {
    livePages.clear();
    const list = Array.isArray(data.settingsPages) ? data.settingsPages : [];
    list.forEach((p, i) => {
        if (!p || typeof p.owner !== 'string') return;
        livePages.add(p.owner);
        const id = 'settings:' + p.owner;
        const known = satelliteDefs.get(p.owner);
        if (known) {
            // The server's list is in label order; a page that started since moves the others along.
            known.label = p.label || p.owner;
            known.order = 20 + i;
            return;
        }
        if (WhipPanel.hasSection(id)) return;
        const def = {
            id, owner: p.owner, label: p.label || p.owner, order: 20 + i,
            title: 'Settings saved here are applied over ' + p.owner + '\'s own defaults',
            hidden: () => !livePages.has(p.owner),
        };
        satelliteDefs.set(p.owner, def);
        makeSettingsSection(def);
    });
});
