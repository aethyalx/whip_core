import { NuiRouter } from './router.js';
import { nuiCallback, clothingIconUrl, clothingPictureName, editorNamesUrl, tattooImageUrl, escapeHtml } from './utils.js';
import { padGlyph } from './pad-glyphs.js';
import { padKeyboardOpen } from './pad-keyboard.js';
import { createPadCursor } from './pad-cursor.js';
import {
    GLYPHS, FEATURE_GROUPS, featureSign, CATEGORIES,
    CLUSTER_ORDER, CLUSTER_LABELS,
    OVERLAY_PALETTE, EYE_COLORS, HAIR_COLORS, MAKEUP_COLORS,
    TATTOO_FACING_YAW, TATTOO_MAX,
} from './creator-data.js';
import { storeAllows, storeChanges, storePrice } from './creator-store.js';

// ========================================
// CHARACTER CREATOR / APPEARANCE EDITOR
//
// One wide panel down the left —
// the groups, the category tabs, the band (the picked item big, and what it can
// be set to; only when the selection has something to show), the card grid —
// and the ped alive in the world on the right. Cards apply instantly (debounced
// preview); Save commits, Cancel walks everything back.
//
// STATE MODEL — the `appearance` object is the single source of truth. The old
// creator kept truth in 80 input elements and re-read them all on every tick;
// here controls mutate `appearance` directly and the DOM is just a view of it.
// collectAppearance() clones it back into the exact saved shape (string-keyed
// components/props, dense 20-float faceFeatures) — that shape is a contract
// with client/appearance.lua and the JSON metadata round-trip. Don't drift it.
// ========================================

let creatorOpen = false;
let isNew = false;
let appearance = null;
let maxVariations = {};
let previewDirty = false;              // a FULL appearance flush is booked
const previewParts = new Map();        // pending small-payload flushes, keyed per control
let previewLoopRunning = false;

let activeCategory = null;      // entry from CATEGORIES
let activeCluster = 'face';     // which of the three rail cards is showing
let activeSubtab = 0;           // index into the category's sub-tabs
let activeFeatureGroup = null;  // entry from FEATURE_GROUPS (features category)
let currentCamPreset = null;
let cancelArmed = null;         // timeout id while Cancel awaits confirmation

// In a store (client/appearance.lua EditAppearance): { only: Set | null, prices, from (the look opened on),
// busy (Save is with the store), why (its last refusal) }; null in the creator and /charedit.
let store = null;
let shownCats = CATEGORIES;         // the tabs offered: a store's only
let shownClusters = CLUSTER_ORDER;  // and the groups that have one

// Chunked grid rendering — big component grids (torso clears 200 drawables)
// append in slices as the list scrolls instead of building 200 nodes up front.
const GRID_CHUNK = 60;
let gridCards = [];
let gridRendered = 0;

const $ = (id) => document.getElementById(id);

function clamp(v, min, max) { return Math.max(min, Math.min(max, v)); }

// ---- swatch palettes ----
//
// The GAME's palettes, read through GetPedHairRgbColor / GetPedMakeupRgbColor
// and delivered with maxVariations, so the swatches match the hair the ped
// actually grows. These fall back to the vendored approximations only if the
// payload is missing, so a swatch never renders blank.
//
// DISPLAY ORDER IS OURS, PALETTE INDICES ARE THE GAME'S. GTA stores these in
// no visual order at all, so a grid that walks 0..63 looks like a jumble. Each
// swatch keeps the index it actually sets on the ped — that mapping is the
// game's and must not move — and only the ORDER they are laid out in changes.
const ACHROMATIC_S = 0.12;   // below this saturation a colour counts as neutral
const HUE_BUCKET   = 24;     // degrees per hue family, so like sits beside like

function hexToRgb(hex) {
    const n = parseInt(String(hex).replace('#', ''), 16);
    return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 };
}

/** @returns [hue 0-360, saturation 0-1, lightness 0-1] */
function rgbToHsl(r, g, b) {
    r /= 255; g /= 255; b /= 255;
    const max = Math.max(r, g, b), min = Math.min(r, g, b);
    const l = (max + min) / 2;
    const d = max - min;
    if (d === 0) return [0, 0, l];
    const s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    let h;
    if (max === r)      h = ((g - b) / d) % 6;
    else if (max === g) h = (b - r) / d + 2;
    else                h = (r - g) / d + 4;
    h *= 60;
    if (h < 0) h += 360;
    return [h, s, l];
}

/**
 * Neutrals first, darkest to lightest — black, through the greys, to white —
 * then the colours by family, each family running dark to light. Ties fall
 * back to the game's own index so the result is stable.
 */
function sortPalette(entries) {
    entries.forEach(e => {
        const hsl = rgbToHsl(e.r, e.g, e.b);
        e.l = hsl[2];
        e.bucket = hsl[1] < ACHROMATIC_S ? -1 : Math.floor(hsl[0] / HUE_BUCKET);
    });
    return entries.sort((a, b) =>
        (a.bucket - b.bucket) || (a.l - b.l) || (a.index - b.index));
}

const paletteCache = {};

function paletteFor(kind) {
    if (paletteCache[kind]) return paletteCache[kind];

    const src = (kind === 'hair') ? maxVariations.hairColors : maxVariations.makeupColors;
    let entries;

    if (src && src.length) {
        entries = src.map((c, i) => ({
            index: i, css: 'rgb(' + c.r + ',' + c.g + ',' + c.b + ')', r: c.r, g: c.g, b: c.b,
        }));
    } else {
        const fallback = (kind === 'hair') ? HAIR_COLORS : MAKEUP_COLORS;
        entries = fallback.map((hex, i) => {
            const c = hexToRgb(hex);
            return { index: i, css: hex, r: c.r, g: c.g, b: c.b };
        });
    }

    paletteCache[kind] = sortPalette(entries);
    return paletteCache[kind];
}

// ========================================
// APPEARANCE NORMALIZATION + COLLECTION
// ========================================

// In GTA's head overlay id order (0 blemishes .. 10 chest hair, client/appearance.lua OVERLAY_IDS): a
// style's name is looked up by its place here (itemName).
const OVERLAY_KEYS = ['blemishes', 'beard', 'eyebrows', 'ageing', 'makeup', 'blush',
                      'complexion', 'sunDamage', 'lipstick', 'moles', 'chestHair'];
const PROP_IDS = [0, 1, 2, 6, 7];

/**
 * Fill every field the editor edits, so no control ever reads undefined. A
 * character saved by an older build (or a fresh default) may be missing keys;
 * after this the object is fully dense and safe to mutate in place.
 */
function normalizeAppearance(a) {
    a = a || {};
    a.model = a.model || 'mp_m_freemode_01';
    a.headBlend = a.headBlend || {};
    const hb = a.headBlend;
    hb.mom = hb.mom || 0; hb.dad = hb.dad || 0; hb.grandparent = hb.grandparent || 0;
    hb.faceWeight = (typeof hb.faceWeight === 'number') ? hb.faceWeight : 0.5;
    hb.skinWeight = (typeof hb.skinWeight === 'number') ? hb.skinWeight : 0.5;
    hb.thirdWeight = (typeof hb.thirdWeight === 'number') ? hb.thirdWeight : 0.0;
    const ff = a.faceFeatures || [];
    a.faceFeatures = [];
    for (let i = 0; i < 20; i++) a.faceFeatures.push(Number(ff[i]) || 0.0);
    a.eyeColor = a.eyeColor || 0;
    a.hair = a.hair || {};
    a.hair.style = a.hair.style || 0; a.hair.texture = a.hair.texture || 0;
    a.hair.color = a.hair.color || 0; a.hair.highlight = a.hair.highlight || 0;
    // Component 2 IS hair. ApplyAppearance sets hair first and runs the
    // components loop after, so when the two disagree, components['2'] is what
    // actually shows on the ped. Adopt it as hair's truth here (legacy saves
    // written by the old UI always carried it), and collectAppearance mirrors
    // hair back into components['2'] so a new save can never disagree again.
    const rawC2 = a.components && a.components['2'];
    if (rawC2 && typeof rawC2.drawable === 'number') {
        a.hair.style = rawC2.drawable;
        a.hair.texture = rawC2.texture || 0;
    }
    a.overlays = a.overlays || {};
    OVERLAY_KEYS.forEach(k => {
        const o = a.overlays[k] || {};
        o.type = o.type || 0;
        o.opacity = (typeof o.opacity === 'number') ? o.opacity : 0.0;
        if (OVERLAY_PALETTE[k]) { o.color = o.color || 0; o.color2 = o.color2 || 0; }
        a.overlays[k] = o;
    });
    a.components = a.components || {};
    for (let i = 0; i <= 11; i++) {
        const c = a.components[String(i)] || {};
        c.drawable = c.drawable || 0; c.texture = c.texture || 0;
        a.components[String(i)] = c;
    }
    a.props = a.props || {};
    PROP_IDS.forEach(i => {
        const p = a.props[String(i)] || {};
        p.drawable = (typeof p.drawable === 'number') ? p.drawable : -1;
        p.texture = p.texture || 0;
        a.props[String(i)] = p;
    });
    // Tattoos are optional in a save (none: no field) and arrive from Lua as an object when empty.
    a.tattoos = (Array.isArray(a.tattoos) ? a.tattoos : [])
        .filter(t => t && typeof t.collection === 'string' && typeof t.overlay === 'string')
        .map(t => ({ collection: t.collection, overlay: t.overlay }));
    // The hair fade (FADES below): one or none (null here; no key in the save).
    const f = a.hairFade;
    a.hairFade = (f && typeof f.collection === 'string' && typeof f.overlay === 'string')
        ? { collection: f.collection, overlay: f.overlay } : null;
    return a;
}

/** Clone state back into the exact saved shape. */
function collectAppearance() {
    return collectAppearanceOf(appearance);
}

function collectAppearanceOf(a) {
    const out = {
        model: a.model,
        headBlend: {
            mom: a.headBlend.mom, dad: a.headBlend.dad, grandparent: a.headBlend.grandparent,
            faceWeight: a.headBlend.faceWeight, skinWeight: a.headBlend.skinWeight,
            thirdWeight: a.headBlend.thirdWeight,
        },
        faceFeatures: a.faceFeatures.slice(0, 20),
        eyeColor: a.eyeColor,
        hair: { style: a.hair.style, texture: a.hair.texture, color: a.hair.color, highlight: a.hair.highlight },
        overlays: {},
        components: {},
        props: {},
    };
    OVERLAY_KEYS.forEach(k => {
        const o = a.overlays[k];
        const c = { type: o.type, opacity: o.opacity };
        if (OVERLAY_PALETTE[k]) { c.color = o.color; c.color2 = o.color2; }
        out.overlays[k] = c;
    });
    for (let i = 0; i <= 11; i++) {
        out.components[String(i)] = { drawable: a.components[String(i)].drawable, texture: a.components[String(i)].texture };
    }
    // Keep components['2'] in lockstep with hair — see normalizeAppearance.
    out.components['2'] = { drawable: a.hair.style, texture: a.hair.texture };
    PROP_IDS.forEach(i => {
        out.props[String(i)] = { drawable: a.props[String(i)].drawable, texture: a.props[String(i)].texture };
    });
    // Sent even when empty, so a preview takes off the ones just tried (the server stores none as none).
    out.tattoos = a.tattoos.map(t => ({ collection: t.collection, overlay: t.overlay }));
    // No fade, no key: a preview without one takes the one tried off (client/appearance.lua applyTattoos).
    if (a.hairFade) out.hairFade = { collection: a.hairFade.collection, overlay: a.hairFade.overlay };
    return out;
}

// FRAME-SYNCED, no fixed delay. Pointer events report faster than the game
// renders (a gaming mouse streams moves at 125-1000Hz against a ~60fps frame),
// so the useful ceiling is exactly one preview per rendered frame — more is
// serialization churn the ped can't display. A dirty flag plus a rAF loop
// gives that: input marks dirty, each animation frame flushes the LATEST state
// (reading live state at flush time), and the loop parks itself the frame
// after input stops — so the final position always lands.
//
// TWO LANES per flush:
//  - FULL (schedulePreview): the whole appearance. For discrete edits — cards,
//    swatches, textures — and for blend sliders (a heritage change re-bakes
//    the head anyway, so the payload isn't the cost there).
//  - PARTS (schedulePartPreview): tiny {kind, ...} payloads for the controls
//    that stream every frame (pads, fine sliders, opacity). Parsing the full
//    ~2-3KB appearance into a fresh Lua table tree each frame was the bulk of
//    the remaining per-frame cost once delta application landed; a part is
//    ~60 bytes. A pending full flush supersedes parts — it carries everything.
function sendPreview() {
    nuiCallback('previewAppearance', { appearance: shownAppearance() });
}

// ========================================
// UNDRESS
//
// One button, all or nothing, at the end of the control
// hints under the cards, so it costs the cards no height. It takes the clothes off to see the body
// under them (tattoos, above all). PREVIEW ONLY: the ped is shown in each slot's "nothing on" item
// (underwear, bare feet: maxVariations.undressed, from client/appearance.lua undressedFor) while
// `appearance` keeps the clothes — Save keeps them, and pressing again puts them back. Picking a piece
// of clothing dresses the ped again, so it can be seen.
// ========================================

// Every clothing slot (0 is the face, 2 hair): what Undress takes off, and what an outfit keeps (OUTFITS).
const CLOTHING_COMPONENTS = [1, 3, 4, 5, 6, 7, 8, 9, 10, 11];
const UNDRESS_PROPS = [0, 1, 2, 6, 7];                         // hat, glasses, ears, watch, bracelet
let undressed = false;

/** What the ped shows: the appearance, or undressed, every slot in its "nothing on" item. */
function shownAppearance() {
    const out = collectAppearance();
    const bare = maxVariations.undressed && maxVariations.undressed.components;
    if (!undressed || !bare) return out;
    CLOTHING_COMPONENTS.forEach(c => {
        const d = bare[String(c)];
        if (typeof d === 'number' && d >= 0) out.components[String(c)] = { drawable: d, texture: 0 };
    });
    UNDRESS_PROPS.forEach(id => { out.props[String(id)] = { drawable: -1, texture: 0 }; });
    return out;
}

function buildUndress() {
    const slot = $('cr-undress');
    slot.innerHTML = maxVariations.undressed
        ? `<button class="cr-dress" data-action="undress" aria-pressed="false">Undress</button>` : '';
    const hint = $('cr-pad-x');   // the pad's X is Undress: no button, no hint
    if (hint) hint.hidden = !maxVariations.undressed;
    markUndress();
}

function markUndress() {
    const el = $('cr-undress').querySelector('.cr-dress');
    if (!el) return;
    el.classList.toggle('on', undressed);
    el.setAttribute('aria-pressed', undressed ? 'true' : 'false');
}

function toggleUndress() {
    undressed = !undressed;
    markUndress();
    schedulePreview();
}

/** A piece of clothing picked: dressed again, so it can be seen. */
function dressAgain() {
    if (!undressed) return;
    undressed = false;
    markUndress();
}

function previewTick() {
    if (!creatorOpen) { previewLoopRunning = false; previewDirty = false; previewParts.clear(); return; }
    if (previewDirty) {
        previewDirty = false;
        previewParts.clear();          // the full snapshot already carries these
        sendPreview();
        requestAnimationFrame(previewTick);
    } else if (previewParts.size) {
        const parts = Array.from(previewParts.values());
        previewParts.clear();
        nuiCallback('previewParts', { parts: parts });
        requestAnimationFrame(previewTick);
    } else {
        previewLoopRunning = false;
        // Settled after a change: a store's price follows it, and its last refusal is gone.
        if (store && !store.busy) { store.why = ''; markStorePrice(); }
    }
}

function schedulePreview() {
    previewDirty = true;
    if (!previewLoopRunning) {
        previewLoopRunning = true;
        requestAnimationFrame(previewTick);
    }
}

function schedulePartPreview(key, part) {
    if (!previewDirty) previewParts.set(key, part);   // a booked full flush already covers it
    if (!previewLoopRunning) {
        previewLoopRunning = true;
        requestAnimationFrame(previewTick);
    }
}

// ========================================
// MAX LOOKUPS
// ========================================

function maxDrawableFor(cat) {
    if (cat.kind === 'component') {
        const m = maxVariations.components && maxVariations.components[String(cat.comp)];
        return m ? m.maxDrawable : 0;
    }
    const m = maxVariations.props && maxVariations.props[String(cat.prop)];
    return m ? m.maxDrawable : 0;
}

function maxOverlayTypes(key) {
    const m = maxVariations.overlays && maxVariations.overlays[key];
    return m ? m.maxType : 0;
}

// ========================================
// CLOTHING PICTURES (img/clothing in whip_media_clothing_male and _female)
//
// maxVariations.icons names every card's item ('<collection>_<item>', asked
// of the game: client/appearance.lua, clothingIcons). A card shows its
// picture once it has LOADED and keeps its glyph and number until then — and
// for good when there is none (added-on clothing, a ped that is not one of
// the two freemode bodies): see the load / error listeners at the bottom.
// ========================================

/** A component's or prop's picture in one colour, or null. */
function iconOf(kind, slot, drawable, texture) {
    const icons = maxVariations.icons;
    if (!icons || drawable < 0) return null;
    const names = kind === 'prop' ? (icons.props || {})[String(slot)] : (icons.components || {})[String(slot)];
    return clothingIconUrl(icons.gender, kind, slot, names && names[drawable], texture);
}

/** A heritage parent's face: the 46 parents are the base game's 46 heads, in the same order. */
function headIconOf(parent) {
    const icons = maxVariations.icons;
    if (!icons) return null;
    return clothingIconUrl(icons.gender, 'component', 0, 'base_' + String(parent).padStart(3, '0'), 0);
}

// ---- names (3D Clanker's) ----
//
// The game's own name for each card's item, shown under its picture instead of its number: a
// clothing or hair item by its picture's name (clothingPictureName — per colour, as the game's shop
// names are), a face option's style as 'overlay_<GTA overlay id>_<style>' (OVERLAY_KEYS is in GTA's
// id order), a heritage parent as 'parent_<n>'. One script in whip_core (editorNamesUrl), loaded the
// first time the creator opens and kept. Until it has come, and for an item the game gives no name,
// a card shows its number. Tattoos carry their own (shared/tattoo_list.lua).
let editorNames = null;
let namesLoading = false;

function loadNames() {
    if (editorNames || namesLoading) return;
    if (window.WHIP_EDITOR_NAMES) { editorNames = window.WHIP_EDITOR_NAMES; return; }
    namesLoading = true;
    const s = document.createElement('script');
    s.src = editorNamesUrl();
    s.onload = () => {
        namesLoading = false;
        editorNames = window.WHIP_EDITOR_NAMES || null;
        if (editorNames && creatorOpen) refreshCardNames();
    };
    s.onerror = () => { namesLoading = false; s.remove(); };   // asked again at the next open
    document.head.appendChild(s);
}

/** The game's name for one card's item in the active category, in colour `texture`, or ''. */
function itemName(value, texture) {
    if (!editorNames || value < 0) return '';
    const cat = activeCategory;
    let key = null;
    if (cat.kind === 'heritage') {
        key = 'parent_' + value;
    } else if (cat.kind === 'overlays') {
        key = 'overlay_' + OVERLAY_KEYS.indexOf(activeOverlayKey()) + '_' + value;
    } else {
        const s = iconSlotOf(cat), icons = maxVariations.icons;
        if (s && icons) {
            const names = s.kind === 'prop' ? (icons.props || {})[String(s.slot)] : (icons.components || {})[String(s.slot)];
            key = clothingPictureName(icons.gender, s.kind, s.slot, names && names[value], texture);
        }
    }
    const name = key && editorNames[key];
    return typeof name === 'string' ? name : '';
}

/** The names arrived: every card's words again, without rebuilding the grid (nor moving its scroll). */
function refreshCardNames() {
    if (!activeCategory || activeCategory.kind === 'tattoos') return;   // tattoos carry their own
    gridCards.forEach(c => { if ('tex' in c) c.name = itemName(c.value, c.tex); });
    const byValue = new Map(gridCards.map(c => [c.value, c]));
    $('cr-grid').querySelectorAll('.cr-card').forEach(el => paintCardLabel(el, byValue.get(Number(el.dataset.value))));
}

// ---- items with no picture ----
//
// GTA's lists carry items that do not exist — their data, nothing to wear — and they are the ones the
// renders have no picture for, so these groups show only what has one. NUMBERS ARE KEPT: a card's
// number is the game's drawable, so the tops run 454, 455, 461 when 456 to 460 are not real.
// An item is left out only when its COLLECTION has pictures and it is not among them, so a collection
// nobody drew (added-on clothing) and an item the game gives no name keep every card.
// Always kept:
//   - THE BASE GAME. Its "nothing" items — no mask, no bag, no vest, no undershirt, the bare top —
//     are real choices with nothing to draw, so they have no picture, and hiding them left no way to
//     take a mask off. The items that do not exist come with the DLC packs.
//   - the item being worn, and the one the editor opened with (a player who picks something else
//     can still go back to it).
// The list comes from the server (server/clothing_pictures.lua), as maxVariations.icons.pictures — or
// a moment after the open (creatorPictures); without one, nothing is left out.
const ONLY_PICTURED = new Set(['apparel', 'props']);   // the groups that do this: Apparel and Accessories
let pictureSets = null;                       // per slot, collection → Set of item numbers; per open
let openedWith = { components: {}, props: {} };   // slot → the drawable the editor opened with

/** '0-3,5,7-9' → Set {0,1,2,3,5,7,8,9} */
function parseRanges(text) {
    const set = new Set();
    for (const part of String(text).split(',')) {
        const m = /^(\d+)(?:-(\d+))?$/.exec(part);
        if (!m) continue;
        const from = Number(m[1]), to = m[2] != null ? Number(m[2]) : from;
        for (let i = from; i <= to && i - from < 1000; i++) set.add(i);
    }
    return set;
}

/** Has this drawable a picture, as far as is known? false only when its collection is listed and it is not. */
function hasPicture(kind, slot, drawable) {
    const icons = maxVariations.icons;
    const group = kind === 'prop' ? 'props' : 'components';
    const listed = icons && icons.pictures && icons.pictures[group];
    if (!listed) return true;
    const names = (icons[group] || {})[String(slot)];
    const m = names && typeof names[drawable] === 'string' && /^(.+)_(\d{3})$/.exec(names[drawable]);
    if (!m || m[1] === 'base') return true;
    if (!pictureSets) pictureSets = new Map();
    const key = group + ':' + slot;
    let collections = pictureSets.get(key);
    if (!collections) {
        collections = new Map();
        const bySlot = listed[String(slot)] || {};
        Object.keys(bySlot).forEach(c => collections.set(c, parseRanges(bySlot[c])));
        pictureSets.set(key, collections);
    }
    const items = collections.get(m[1]);
    return !items || items.has(Number(m[2]));
}

function iconImg(src) {
    return src ? `<img class="cr-icon" src="${src}" alt="" loading="lazy" decoding="async" draggable="false">` : '';
}

// ========================================
// TATTOOS
//
// maxVariations.tattoos (client/appearance.lua, tattoosFor): what this body can wear and this game
// has, per part of the body — zones[zone] = [ [collection number (1-based), overlay, facing, name], ... ],
// collections = [ { name, label } ]. appearance.tattoos is what is worn, { collection, overlay } in the
// order put on. A card's value is its place in its part's list, its number that place + 1 (numbers
// move when a game update adds tattoos before it, as the clothing numbers do: the save keeps names).
// A card is the tattoo's picture (whip_media_previews/img/tattoos, 3D Clanker's flash cards) and its name; one
// with no picture keeps the anchor, one with no name (the base game's) its number. No band (renderOptions).
// ========================================

let tattooFull = false;    // a tattoo was refused for being one more than TATTOO_MAX

function tattooZone(zone) {
    const t = maxVariations.tattoos;
    return (t && t.zones && Array.isArray(t.zones[zone])) ? t.zones[zone] : [];
}

/** One tattoo of a part, by card value: { collection, overlay, facing, from, name } (from: the collection
 *  in words; name: '' when it has none). */
function tattooAt(zone, i) {
    const row = tattooZone(zone)[i];
    const cols = maxVariations.tattoos && maxVariations.tattoos.collections;
    const col = row && cols && cols[row[0] - 1];
    if (!col) return null;
    return { collection: col.name, overlay: row[1], facing: row[2], from: col.label, name: row[3] || '' };
}

/** The game's hashes ignore case, so the list's spelling and a save's are compared without it. */
function tattooKey(collection, overlay) { return (collection + '/' + overlay).toLowerCase(); }

function wornTattooKeys() { return new Set(appearance.tattoos.map(t => tattooKey(t.collection, t.overlay))); }

function tattooWorn(worn, zone, i) {
    const t = tattooAt(zone, i);
    return !!t && worn.has(tattooKey(t.collection, t.overlay));
}

/** Repaint which cards are on, rendered or not yet: many can be, so markSelectedCard's one won't do. */
function markTattooCards() {
    const worn = wornTattooKeys(), zone = activeCategory.zone;
    let any = false;
    gridCards.forEach(c => { if (c.value >= 0) { c.selected = tattooWorn(worn, zone, c.value); any = any || c.selected; } });
    gridCards.forEach(c => { if (c.value < 0) c.selected = !any; });
    const byValue = new Map(gridCards.map(c => [c.value, c]));
    $('cr-grid').querySelectorAll('.cr-card').forEach(el => {
        const c = byValue.get(Number(el.dataset.value));
        const on = !!(c && c.selected);
        el.classList.toggle('selected', on);
        el.setAttribute('aria-pressed', on ? 'true' : 'false');
    });
}

/** A tattoo card pressed: on if it was off, off if it was on; None takes off every tattoo of this part. */
function onTattooCard(value) {
    const zone = activeCategory.zone;
    if (value === -1) {
        const here = new Set(tattooZone(zone).map((_, i) => {
            const t = tattooAt(zone, i);
            return t ? tattooKey(t.collection, t.overlay) : '';
        }));
        appearance.tattoos = appearance.tattoos.filter(t => !here.has(tattooKey(t.collection, t.overlay)));
        tattooFull = false;
    } else {
        const t = tattooAt(zone, value);
        if (!t) return;
        const key = tattooKey(t.collection, t.overlay);
        const at = appearance.tattoos.findIndex(w => tattooKey(w.collection, w.overlay) === key);
        if (at >= 0) {
            appearance.tattoos.splice(at, 1);
            tattooFull = false;
        } else if (appearance.tattoos.length >= TATTOO_MAX) {
            tattooFull = true;          // nothing changes; the band says why
            renderOptions();
            return;
        } else {
            appearance.tattoos.push({ collection: t.collection, overlay: t.overlay });
            // Turn to it: a tattoo on the back is no use seen from the front. The game does not say
            // the side of the base game's tattoos, and those leave the camera where it is.
            const yaw = TATTOO_FACING_YAW[t.facing];
            if (typeof yaw === 'number') nuiCallback('switchCamera', { yaw: yaw });
        }
    }
    markTattooCards();
    schedulePreview();
    renderOptions();
}

// ========================================
// HAIR FADES
//
// maxVariations.fades (client/appearance.lua, fadesFor): the fades this body can wear and this game has,
// list = [ [collection number (1-based), overlay], ... ], collections = [ { name, label } ]. A fade is the
// stubble drawn on the scalp under the hairstyle, a decoration put on with the tattoos, picked on the Hair
// tab's Fade sub-tab: one, or None. The game names none and whip has no pictures of them, so a card is its
// number (its place in the list + 1) and the band says which update it came with.
// ========================================

const HAIR_FADE_TAB = 1;      // the Hair tab's sub-tab for fades (subtabsFor)
const FADE_YAW = 270;         // the camera turns to the side of the head for them (the ped's left)

function fadeList() {
    const f = maxVariations.fades;
    return (f && Array.isArray(f.list)) ? f.list : [];
}

/** One fade by card value: { collection, overlay, from }, or null. */
function fadeAt(i) {
    const row = fadeList()[i];
    const cols = maxVariations.fades && maxVariations.fades.collections;
    const col = row && cols && cols[row[0] - 1];
    return col ? { collection: col.name, overlay: row[1], from: col.label } : null;
}

/** The card value of the fade worn, or -1 for none. Compared as the tattoos are (the game ignores case). */
function wornFadeIndex() {
    const w = appearance.hairFade;
    if (!w) return -1;
    const key = tattooKey(w.collection, w.overlay);
    return fadeList().findIndex((_, i) => {
        const f = fadeAt(i);
        return !!f && tattooKey(f.collection, f.overlay) === key;
    });
}

function onFadeCard(value) {
    const f = value >= 0 ? fadeAt(value) : null;
    appearance.hairFade = f ? { collection: f.collection, overlay: f.overlay } : null;
    markSelectedCard(f ? value : -1);
    schedulePreview();
    renderOptions();
}

// ========================================
// OUTFITS
//
// The character's saved outfits: the clothes and accessories they had on (every clothing slot and prop,
// never the face, hair or tattoos), kept by name on the character by the server (server/events_misc.lua,
// metadata `outfits`). A save, an update, a rename and a delete are kept at once, whatever Save or Cancel
// does after. A card puts one on: an edit like any other card's, kept by Save and walked back by Cancel.
// The cards are this body's outfits only (`model`: a drawable number is another item on the other body),
// lit when every slot of it is what is on, so two saved alike are both lit. The band names what is on:
// the outfit worn, to rename or delete; or, when it is none, a name to save it under, and Save over the
// outfit put on here last (it was changed since).
// ========================================

const OUTFIT_NAME_MAX = 30;       // the server's OUTFIT_NAME_MAX
let outfits = [];                 // every body's, as the server keeps them: { id, name, model, components, props }
let outfitMax = 20;               // Config.Creator.maxOutfits (the server holds to it)
let outfitLast = null;            // the id of the outfit put on or saved here last: Save over's
let outfitWhy = '';               // the server's last refusal, said in the band until the next press
let outfitBusy = false;           // a press is with the server: the band's buttons wait for its answer
let outfitDeleteArmed = null;     // timeout id while Delete waits for its second press

function normalizeOutfits(list) {
    return (Array.isArray(list) ? list : []).filter(o => o && typeof o.id === 'number' && typeof o.name === 'string'
        && typeof o.model === 'string' && o.components && typeof o.components === 'object'
        && o.props && typeof o.props === 'object');
}

/** This body's outfits, in the order they were saved. */
function outfitsHere() { return outfits.filter(o => o.model === appearance.model); }

/** What the character has on, as an outfit: the real clothes (Undress is only a preview). */
function outfitOfAppearance() {
    const o = { model: appearance.model, components: {}, props: {} };
    CLOTHING_COMPONENTS.forEach(c => {
        const s = appearance.components[String(c)];
        o.components[String(c)] = { drawable: s.drawable, texture: s.texture };
    });
    PROP_IDS.forEach(p => {
        const s = appearance.props[String(p)];
        o.props[String(p)] = { drawable: s.drawable, texture: s.texture };
    });
    return o;
}

/** The same item in the same colour (a prop taken off is off, whatever colour it was). */
function sameItem(a, b) {
    return !!a && !!b && a.drawable === b.drawable && (a.drawable === -1 || a.texture === b.texture);
}

function wearingOutfit(o) {
    return o.model === appearance.model
        && CLOTHING_COMPONENTS.every(c => sameItem(o.components[String(c)], appearance.components[String(c)]))
        && PROP_IDS.every(p => sameItem(o.props[String(p)], appearance.props[String(p)]));
}

/** The outfit on now: the one put on last when it is, else the first saved that is. */
function outfitWorn() {
    const here = outfitsHere();
    return here.find(o => o.id === outfitLast && wearingOutfit(o)) || here.find(wearingOutfit) || null;
}

/** An outfit's picture: its top's, as the cards and the band show it. */
function outfitIcon(o) {
    const top = o.components['11'];
    return top ? iconOf('component', 11, top.drawable, top.texture) : null;
}

/** What the server calls an outfit saved with no name: "Outfit N", the first N no outfit is called. */
function defaultOutfitName() {
    const taken = new Set(outfits.map(o => o.name));
    let n = outfits.length + 1;
    while (taken.has('Outfit ' + n)) n++;
    return 'Outfit ' + n;
}

function onOutfitCard(value) {
    const o = outfits.find(x => x.id === value);
    if (!o) return;
    disarmOutfitDelete();
    outfitWhy = '';
    CLOTHING_COMPONENTS.forEach(c => {
        const s = o.components[String(c)];
        if (s) appearance.components[String(c)] = { drawable: s.drawable, texture: s.texture };
    });
    PROP_IDS.forEach(p => {
        const s = o.props[String(p)];
        if (s) appearance.props[String(p)] = { drawable: s.drawable, texture: s.texture };
    });
    outfitLast = o.id;
    dressAgain();                 // undressed, it would not show
    markOutfitCards();
    schedulePreview();
    renderOptions();
}

/** Repaint which cards are on (any number can be: two outfits saved alike). */
function markOutfitCards() {
    const on = new Set(outfitsHere().filter(wearingOutfit).map(o => o.id));
    gridCards.forEach(c => { c.selected = on.has(c.value); });
    $('cr-grid').querySelectorAll('.cr-card').forEach(el => {
        const lit = on.has(Number(el.dataset.value));
        el.classList.toggle('selected', lit);
        el.setAttribute('aria-pressed', lit ? 'true' : 'false');
    });
}

/** The band: the outfit worn (its name, to change, and Delete), or what is on with a name to save it under. */
function renderOutfitBand() {
    const worn = outfitWorn();
    const last = !worn && outfitLast != null ? outfitsHere().find(o => o.id === outfitLast) || null : null;
    const full = outfits.length >= outfitMax;
    const wait = outfitBusy ? ' disabled' : '';
    const box = (value, placeholder) => `<input id="cr-outfit-name" class="cr-input" type="text" maxlength="${OUTFIT_NAME_MAX}"`
        + ` value="${escapeHtml(value)}" placeholder="${escapeHtml(placeholder)}" spellcheck="false" autocomplete="off"`
        + ` aria-label="Outfit name"${wait}>`;
    let body = `<div class="cr-opt-label"><span>Name</span></div>`;
    if (worn) {
        body += `<div class="cr-outfit-row">${box(worn.name, worn.name)}`
            + `<button class="cr-obtn" data-action="outfitRename" data-value="${worn.id}"${wait}>Rename</button></div>`
            + `<div class="cr-outfit-row"><button class="cr-obtn cr-obtn-quiet" id="cr-outfit-delete" data-action="outfitDelete"`
            + ` data-value="${worn.id}"${wait}>Delete outfit</button></div>`;
    } else {
        body += `<div class="cr-outfit-row">${box('', defaultOutfitName())}`
            + `<button class="cr-obtn cr-obtn-primary" data-action="outfitSave"${outfitBusy || full ? ' disabled' : ''}>Save outfit</button></div>`
            + (last ? `<div class="cr-outfit-row"><button class="cr-obtn" data-action="outfitUpdate" data-value="${last.id}"${wait}>`
                + `Save over ${escapeHtml(last.name)}</button></div>` : '')
            + (full ? `<div class="cr-opt-hint cr-opt-warn">${outfitMax} outfits is the most one character keeps. Delete one to save another.</div>` : '');
    }
    if (!outfitsHere().length) {
        body += `<div class="cr-opt-hint">An outfit keeps the clothes and accessories on now, to put on again with one press.`
            + ` The face, hair and tattoos stay as they are.</div>`;
    }
    if (outfitWhy) body += `<div class="cr-opt-hint cr-opt-warn">${escapeHtml(outfitWhy)}</div>`;
    setOptions(worn ? escapeHtml(worn.name) : 'New outfit', body, {
        src: outfitIcon(outfitOfAppearance()), glyph: 'outfit',
        sub: worn ? 'You have this outfit on' : last ? `${escapeHtml(last.name)}, changed` : 'What you have on is not saved',
        meta: `${outfits.length} of ${outfitMax} saved`,
    });
}

/** One press to the server (client/appearance.lua passes it on). Its answer is the whole list, or why not. */
function outfitCall(name, data, after) {
    if (outfitBusy) return;
    outfitBusy = true;
    outfitWhy = '';
    disarmOutfitDelete();
    renderOptions();                 // its buttons wait
    nuiCallback(name, data).then(resp => {
        outfitBusy = false;
        if (!creatorOpen) return;
        if (resp && resp.ok) {
            outfits = normalizeOutfits(resp.outfits);
            if (after) after();
        } else {
            outfitWhy = (resp && typeof resp.why === 'string' && resp.why) || 'That did not save. Try again.';
        }
        if (activeCategory && activeCategory.kind === 'outfits') { renderGrid(); renderOptions(); }
    });
}

function typedOutfitName() {
    const box = $('cr-outfit-name');
    return box ? box.value.trim() : '';
}

function saveOutfit() {
    const before = new Set(outfits.map(o => o.id));
    outfitCall('saveOutfit', { name: typedOutfitName(), outfit: outfitOfAppearance() }, () => {
        const made = outfits.find(o => !before.has(o.id));
        if (made) outfitLast = made.id;
    });
}

function updateOutfit(id) {
    outfitCall('updateOutfit', { id, outfit: outfitOfAppearance() }, () => { outfitLast = id; });
}

function renameOutfit(id) {
    outfitCall('renameOutfit', { id, name: typedOutfitName() });
}

// Delete arms first, as Cancel does: one press turns it into "Delete?", a second within 3 s deletes.
function deleteOutfit(el) {
    const id = Number(el.dataset.value);
    if (!outfitDeleteArmed) {
        el.classList.add('armed');
        el.textContent = 'Delete?';
        outfitDeleteArmed = setTimeout(disarmOutfitDelete, 3000);
        return;
    }
    outfitCall('deleteOutfit', { id }, () => { if (outfitLast === id) outfitLast = null; });
}

function disarmOutfitDelete() {
    if (outfitDeleteArmed) clearTimeout(outfitDeleteArmed);
    outfitDeleteArmed = null;
    const el = $('cr-outfit-delete');
    if (el) { el.classList.remove('armed'); el.textContent = 'Delete outfit'; }
}

/** What the active category's pictures are: { kind, slot } for clothing and hair, else null. */
function iconSlotOf(cat) {
    if (cat.kind === 'component') return { kind: 'component', slot: cat.comp };
    if (cat.kind === 'prop') return { kind: 'prop', slot: cat.prop };
    if (cat.kind === 'hair') return { kind: 'component', slot: 2 };
    return null;
}

// ========================================
// RAIL
// ========================================

// A switch and then a list: the three groups choose, and only that group's
// categories are offered. The groups are the main
// menu's words at the top of the panel, the categories a row of the Director's
// tabs under them.
function buildRail() {
    $('cr-groups').innerHTML = shownClusters.map(key => {
        const on = key === activeCluster;
        return `<button class="cr-group${on ? ' active' : ''}" data-action="cluster" data-cluster="${key}"
            aria-pressed="${on}">${CLUSTER_LABELS[key] || key}</button>`;
    }).join('');

    $('cr-rail').innerHTML = shownCats.filter(cat => cat.cluster === activeCluster).map(cat =>
        `<button class="cr-tab" data-action="category" data-cat="${cat.id}">${cat.label}</button>`).join('');
    markActiveRail();
}

function markActiveRail() {
    $('cr-rail').querySelectorAll('.cr-tab').forEach(el => {
        const on = !!(activeCategory && el.dataset.cat === activeCategory.id);
        el.classList.toggle('active', on);
        el.setAttribute('aria-pressed', on ? 'true' : 'false');
    });
}

/** Switch groups by opening that group's first category — selectCategory owns
 *  activeCluster and the rebuild, so this must NOT set the cluster itself:
 *  doing that made selectCategory think nothing had changed, and the rail kept
 *  listing the old group while the grid showed the new one. */
function selectCluster(key) {
    if (!key || key === activeCluster) return;
    const first = shownCats.find(c => c.cluster === key);
    if (first) selectCategory(first.id);
}

// ========================================
// CATEGORY SWITCHING
// ========================================

function subtabsFor(cat) {
    if (cat.kind === 'heritage') {
        return [{ label: 'Mother' }, { label: 'Father' }, { label: 'Grandparent' }];
    }
    if (cat.kind === 'overlays' && cat.overlays.length > 1) return cat.overlays;
    if (cat.kind === 'hair' && fadeList().length) return [{ label: 'Hairstyle' }, { label: 'Fade' }];   // HAIR_FADE_TAB
    return null;
}

function selectCategory(id) {
    const cat = CATEGORIES.find(c => c.id === id);
    if (!cat) return;
    activeCategory = cat;
    activeSubtab = 0;
    activeFeatureGroup = null;
    texExpanded = false;
    tattooFull = false;

    // Keep the rail's group card in step, whether the category was picked from
    // the list or jumped to programmatically (the creator opens on Heritage).
    if (cat.cluster !== activeCluster) {
        activeCluster = cat.cluster;
        buildRail();
    } else {
        markActiveRail();
    }

    // Camera glides only when the framing actually changes — a same-preset
    // switch (mask → hat) shouldn't twitch the shot. A category with a `yaw`
    // (the tattoo parts) also turns it round the ped, framing or not.
    const turn = typeof cat.yaw === 'number';
    if (cat.cam !== currentCamPreset || turn) {
        const shot = {};
        if (cat.cam !== currentCamPreset) { currentCamPreset = cat.cam; shot.preset = cat.cam; }
        if (turn) shot.yaw = cat.yaw;
        nuiCallback('switchCamera', shot);
    }

    renderSubtabs();
    renderGrid();
    renderOptions();
}

function renderSubtabs() {
    const bar = $('cr-subtabs');
    const tabs = subtabsFor(activeCategory);
    if (!tabs) { bar.innerHTML = ''; bar.style.display = 'none'; return; }
    bar.style.display = '';
    bar.innerHTML = tabs.map((t, i) =>
        `<button class="cr-subtab${i === activeSubtab ? ' active' : ''}" data-action="subtab" data-idx="${i}"`
        + ` aria-pressed="${i === activeSubtab}">${t.label}</button>`
    ).join('');
}

function selectSubtab(idx) {
    activeSubtab = idx;
    texExpanded = false;
    // A fade is on the sides and back of the head: the camera turns to the side for them.
    if (activeCategory.kind === 'hair' && idx === HAIR_FADE_TAB) nuiCallback('switchCamera', { yaw: FADE_YAW });
    renderSubtabs();
    renderGrid();
    renderOptions();
}

/** The overlay key the grid/options are currently editing (overlays kind). */
function activeOverlayKey() {
    return activeCategory.overlays[activeSubtab] ? activeCategory.overlays[activeSubtab].key : activeCategory.overlays[0].key;
}

// ========================================
// CARD GRID
//
// gridCards is a flat descriptor list; chunks of it become DOM as the grid
// scrolls. Every card carries data-action="card" data-value — what the value
// means is the active category's business (drawable id, parent id, overlay
// type, feature group index...).
// ========================================

/** What one card is, for a screen reader: "Top 5", "Mother 21", "Beard 3"; a named card ("None",
 *  "Brow", an eye colour, a tattoo's name) is its own name. */
function cardName(c) {
    if (c.name) return escapeHtml(c.name);
    if (!/^\d+$/.test(c.label)) return c.label;
    const cat = activeCategory;
    const noun = cat.kind === 'heritage' ? ['Mother', 'Father', 'Grandparent'][activeSubtab]
        : cat.kind === 'overlays' ? cat.overlays[activeSubtab].label
        : cat.kind === 'hair' && activeSubtab === HAIR_FADE_TAB ? 'Fade'
        : cat.kind === 'tattoos' ? `${cat.label} tattoo`
        : (cat.one || cat.label);
    return `${noun} ${c.label}`;
}

// UNDER THE PICTURE, ITS NAME WHEN IT HAS ONE, its number when not: `c.name` is the
// game's own name for the item (itemName; a tattoo's from its list), unescaped. The band above keeps
// the number. `c.tex`, on a card that can have a name, is the colour its picture and name are of.
function cardLabel(c) {
    return c.name ? `<span class="cr-card-num cr-card-name">${escapeHtml(c.name)}</span>`
        : `<span class="cr-card-num">${c.label}</span>`;
}

/** One rendered card's words, again (its name came, or its colour changed). */
function paintCardLabel(el, c) {
    const label = el && c && el.querySelector('.cr-card-num');
    if (!label) return;
    label.outerHTML = cardLabel(c);
    el.classList.toggle('named', !!c.name);
    el.setAttribute('aria-label', cardName(c));
}

// A real button, so the keyboard reaches it; its picture is decoration (alt="").
function cardHtml(c) {
    const sel = c.selected ? ' selected' : '';
    const art = c.swatch
        ? `<span class="cr-card-swatch" style="background:${c.swatch}"></span>`
        : `<span class="cr-card-art">${GLYPHS[c.glyph] || GLYPHS.face}</span>`;
    return `<button type="button" class="cr-card${sel}${c.name ? ' named' : ''}" data-action="card" data-value="${c.value}"
        aria-pressed="${!!c.selected}" aria-label="${cardName(c)}">
        ${art}${iconImg(c.icon)}${cardLabel(c)}</button>`;
}

function buildGridCards() {
    const cat = activeCategory;
    const cards = [];

    if (cat.kind === 'heritage') {
        const key = ['mom', 'dad', 'grandparent'][activeSubtab];
        const max = (activeSubtab === 1) ? 44 : 45;   // dads run 0-44, moms/grandparents 0-45
        const cur = appearance.headBlend[key];
        for (let i = 0; i <= max; i++) {
            cards.push({ value: i, label: String(i), glyph: 'face', selected: cur === i, icon: headIconOf(i),
                         tex: 0, name: itemName(i, 0) });
        }
    } else if (cat.kind === 'features') {
        FEATURE_GROUPS.forEach((g, i) => {
            cards.push({ value: i, label: g.label, glyph: g.glyph,
                         selected: activeFeatureGroup === g });
        });
    } else if (cat.kind === 'eyes') {
        EYE_COLORS.forEach((e, i) => {
            cards.push({ value: i, label: e.name, swatch: e.hex, selected: appearance.eyeColor === i });
        });
    } else if (cat.kind === 'hair' && activeSubtab === HAIR_FADE_TAB) {
        // One fade or none; a card is the fade's number (no names, no pictures).
        const worn = wornFadeIndex();
        cards.push({ value: -1, label: 'None', glyph: 'none', selected: worn === -1 });
        fadeList().forEach((_, i) => cards.push({ value: i, label: String(i + 1), glyph: 'fade', selected: worn === i }));
    } else if (cat.kind === 'hair') {
        const max = (maxVariations.hair && maxVariations.hair.maxStyle) || 0;
        const h = appearance.hair;
        for (let i = 0; i < max; i++) {
            const tex = h.style === i ? h.texture : 0;
            cards.push({ value: i, label: String(i), glyph: 'hair', selected: h.style === i,
                         icon: iconOf('component', 2, i, tex), tex, name: itemName(i, tex) });
        }
    } else if (cat.kind === 'overlays') {
        const key = activeOverlayKey();
        const o = appearance.overlays[key];
        const off = o.opacity === 0;
        cards.push({ value: -1, label: 'None', glyph: 'none', selected: off });
        const max = maxOverlayTypes(key);
        for (let i = 0; i < max; i++) {
            cards.push({ value: i, label: String(i), glyph: cat.glyph, selected: !off && o.type === i,
                         tex: 0, name: itemName(i, 0) });
        }
    } else if (cat.kind === 'component') {
        const c = appearance.components[String(cat.comp)];
        const max = maxDrawableFor(cat);
        const only = ONLY_PICTURED.has(cat.cluster), opened = openedWith.components[String(cat.comp)];
        for (let i = 0; i < max; i++) {
            if (only && i !== c.drawable && i !== opened && !hasPicture('component', cat.comp, i)) continue;
            const tex = c.drawable === i ? c.texture : 0;
            cards.push({ value: i, label: String(i), glyph: cat.glyph, selected: c.drawable === i,
                         icon: iconOf('component', cat.comp, i, tex), tex, name: itemName(i, tex) });
        }
    } else if (cat.kind === 'prop') {
        const p = appearance.props[String(cat.prop)];
        cards.push({ value: -1, label: 'None', glyph: 'none', selected: p.drawable === -1 });
        const max = maxDrawableFor(cat);
        const only = ONLY_PICTURED.has(cat.cluster), opened = openedWith.props[String(cat.prop)];
        for (let i = 0; i < max; i++) {
            if (only && i !== p.drawable && i !== opened && !hasPicture('prop', cat.prop, i)) continue;
            const tex = p.drawable === i ? p.texture : 0;
            cards.push({ value: i, label: String(i), glyph: cat.glyph, selected: p.drawable === i,
                         icon: iconOf('prop', cat.prop, i, tex), tex, name: itemName(i, tex) });
        }
    } else if (cat.kind === 'tattoos') {
        // Any number on at once; None is "none of this part", lit when that is so.
        const worn = wornTattooKeys();
        const list = tattooZone(cat.zone);
        const none = { value: -1, label: 'None', glyph: 'none', selected: true };
        cards.push(none);
        for (let i = 0; i < list.length; i++) {
            const on = tattooWorn(worn, cat.zone, i);
            if (on) none.selected = false;
            cards.push({ value: i, label: String(i + 1), glyph: cat.glyph, selected: on, icon: tattooImageUrl(list[i][1]),
                         name: list[i][3] || '' });
        }
    } else if (cat.kind === 'outfits') {
        // A card's value is the outfit's id; its picture is its top.
        outfitsHere().forEach(o => {
            cards.push({ value: o.id, label: '', glyph: cat.glyph, selected: wearingOutfit(o), icon: outfitIcon(o), name: o.name });
        });
    }
    return cards;
}

function renderGrid() {
    const grid = $('cr-grid');
    gridCards = buildGridCards();
    gridRendered = 0;
    grid.innerHTML = '';
    grid.scrollTop = 0;
    appendGridChunk();
    // Land the view on the current selection rather than making the player
    // scroll a 200-card grid hunting for their own jacket — wherever it is:
    // five to a row, card 15 is already below the fold.
    const idx = gridCards.findIndex(c => c.selected);
    while (idx >= 0 && gridRendered <= idx && gridRendered < gridCards.length) appendGridChunk();
    revealSelectedCard(true);
    reportGridHitTest();
}

/**
 * Scroll the grid (and only the grid) so the picked card is in view: to the middle for a new grid,
 * or just enough when the band above changed height and pushed it out. By hand, not scrollIntoView:
 * that scrolls every scroller up the tree, the panel included. offsetTop is the card's place in the
 * grid's content (the grid is its offsetParent), whatever the scroll.
 */
function revealSelectedCard(centre) {
    // MANY CARDS ARE LIT IN THE TATTOOS, and the first of them is not the one pressed: following it
    // would throw the list back to the top on every press. The one pressed is under the
    // pointer already, so only a new grid is moved there (to the first one worn).
    if (!centre && activeCategory && activeCategory.kind === 'tattoos') return;
    const grid = $('cr-grid');
    const el = grid.querySelector('.cr-card.selected');
    if (!el || !grid.clientHeight) return;
    revealIn(grid, el, centre);
}

function revealIn(box, el, centre) {
    const top = el.offsetTop, bottom = top + el.offsetHeight, room = box.clientHeight;
    if (centre) {
        box.scrollTop = Math.max(0, top - (room - el.offsetHeight) / 2);
    } else if (top - 4 < box.scrollTop) {
        box.scrollTop = Math.max(0, top - 4);
    } else if (bottom + 4 > box.scrollTop + room) {
        box.scrollTop = bottom + 4 - room;
    }
}

function appendGridChunk() {
    if (gridRendered >= gridCards.length) return;
    const grid = $('cr-grid');
    const slice = gridCards.slice(gridRendered, gridRendered + GRID_CHUNK);
    const frag = document.createElement('div');
    frag.innerHTML = slice.map(cardHtml).join('');
    while (frag.firstChild) grid.appendChild(frag.firstChild);
    gridRendered += slice.length;
}

function onGridScroll() {
    const grid = $('cr-grid');
    if (grid.scrollTop + grid.clientHeight > grid.scrollHeight - 300) appendGridChunk();
}

/**
 * One line to the console naming what actually sits on top of the first row of
 * cards. Cards in the second and third column once ignored the mouse entirely
 * while everything around them worked; if that ever comes back, this says
 * whether the card is genuinely on top at its own centre (so the problem is in
 * the handler) or whether some other element is (so it is a layering problem),
 * without another round of guessing. Cheap, runs once per category switch.
 */
function reportGridHitTest() {
    try {
        const cards = $('cr-grid').querySelectorAll('.cr-card');
        const out = [];
        for (let i = 0; i < Math.min(3, cards.length); i++) {
            const r = cards[i].getBoundingClientRect();
            const hit = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
            const ok = hit === cards[i] || cards[i].contains(hit);
            out.push('#' + i + (ok ? ' ok' : ' BLOCKED by .' + (hit ? (hit.className || hit.tagName) : 'nothing')));
        }
        // The drag surface gets the same check. Its width is the other half of
        // the same layout question: the left column and the stage share one
        // flex row, so whenever one is wrong the other is too — the stage
        // collapsed to nothing the moment the card list started reporting a
        // different intrinsic width.
        const stage = $('cr-stage');
        const sr = stage.getBoundingClientRect();
        const sHit = document.elementFromPoint(sr.left + sr.width / 2, sr.top + sr.height / 2);
        const sOk = sHit === stage;
        out.push('stage ' + Math.round(sr.width) + 'px ' + (sOk ? 'ok' : 'BLOCKED by .' + (sHit ? (sHit.className || sHit.tagName) : 'nothing')));

        console.log('[creator] hit-test: ' + out.join(' | '));
    } catch (err) { /* diagnostics must never break the screen */ }
}

/** Point a grid card's picture, and its name, at a colour: the one picked for the item worn, 0 for the rest. */
function setCardIcon(value, texture) {
    const s = iconSlotOf(activeCategory);
    if (!s || value < 0) return;
    const el = $('cr-grid').querySelector(`.cr-card[data-value="${value}"]`);
    const card = gridCards.find(c => c.value === value);
    if (card && 'tex' in card) {
        card.tex = texture;
        card.name = itemName(value, texture);
        paintCardLabel(el, card);
    }
    const src = el && iconOf(s.kind, s.slot, value, texture);
    if (!src) return;
    const img = el.querySelector('img.cr-icon');
    if (img) {
        if (img.getAttribute('src') !== src) img.setAttribute('src', src);
    } else {
        // Its last picture did not load (that colour has none): try this one.
        el.querySelector('.cr-card-num').insertAdjacentHTML('beforebegin', iconImg(src));
    }
}

/** Repaint which card is selected without rebuilding the grid. */
function markSelectedCard(value) {
    $('cr-grid').querySelectorAll('.cr-card').forEach(el => {
        const on = Number(el.dataset.value) === value;
        el.classList.toggle('selected', on);
        el.setAttribute('aria-pressed', on ? 'true' : 'false');
    });
}

// ========================================
// CARD CLICKS
// ========================================

function onCardClick(el) {
    const value = Number(el.dataset.value);
    const cat = activeCategory;

    if (cat.kind === 'heritage') {
        const key = ['mom', 'dad', 'grandparent'][activeSubtab];
        appearance.headBlend[key] = value;
        markSelectedCard(value);
        schedulePreview();
        renderOptions();              // the band shows the parent picked
    } else if (cat.kind === 'features') {
        activeFeatureGroup = FEATURE_GROUPS[value] || null;
        markSelectedCard(value);
        renderOptions();
        return;                       // picking a group changes no appearance
    } else if (cat.kind === 'eyes') {
        appearance.eyeColor = value;
        markSelectedCard(value);
        schedulePreview();
        return;                       // eye color has no options panel
    } else if (cat.kind === 'hair' && activeSubtab === HAIR_FADE_TAB) {
        onFadeCard(value);
        return;
    } else if (cat.kind === 'hair') {
        const was = appearance.hair.style;
        appearance.hair.style = value;
        appearance.hair.texture = 0;  // texture counts differ per style
        if (was !== value) { setCardIcon(was, 0); texExpanded = false; }
        markSelectedCard(value);
        schedulePreview();
        renderOptions();              // refresh the texture row for this style
        return;
    } else if (cat.kind === 'overlays') {
        const key = activeOverlayKey();
        const o = appearance.overlays[key];
        if (value === -1) {
            o.opacity = 0.0; o.type = 0;   // type 0 + opacity 0 = the clear signal (see ApplyAppearance)
        } else {
            o.type = value;
            if (o.opacity === 0) o.opacity = 1.0;   // picking a style should be visible immediately
        }
        markSelectedCard(value);
        schedulePreview();
        renderOptions();              // opacity slider needs its new value
        return;
    } else if (cat.kind === 'component') {
        const c = appearance.components[String(cat.comp)];
        const was = c.drawable;
        c.drawable = value;
        c.texture = 0;                // texture counts differ per drawable
        if (was !== value) { setCardIcon(was, 0); texExpanded = false; }
        markSelectedCard(value);
        dressAgain();                 // undressed, it would not show
        schedulePreview();
        renderOptions();
        return;
    } else if (cat.kind === 'prop') {
        const p = appearance.props[String(cat.prop)];
        const was = p.drawable;
        p.drawable = value;
        p.texture = 0;
        if (was !== value) { setCardIcon(was, 0); texExpanded = false; }
        markSelectedCard(value);
        dressAgain();
        schedulePreview();
        renderOptions();
        return;
    } else if (cat.kind === 'tattoos') {
        onTattooCard(value);
        return;
    } else if (cat.kind === 'outfits') {
        onOutfitCard(value);
        return;
    }
}

// ========================================
// OPTIONS PANEL
// ========================================

/**
 * THE BAND: the picked item's options, at the top of the panel above the grid, beside a big picture of the picked item when it has one.
 *   title    the band's heading ("Top 5", "Blend")
 *   bodyHtml its controls ('' for none)
 *   hero     { src, glyph, sub, meta } or null: the picture (src null = its glyph until there is one),
 *            the line under the heading (the item's collection) and the small count under that
 *   side     controls that stand beside the picture, filling its height (hair's two colour grids, one
 *            over the other). The heading goes up to a line of its own above them, with the collection
 *            beside it and `bodyHtml` at its end (hair's textures), so the band is the picture's height
 *            and a line, and the grid under it keeps its rows of cards.
 * Neither controls nor a picture (eyes; "None" picked): the band goes and the grid takes its room.
 */
function setOptions(title, bodyHtml, hero, side) {
    const band = $('cr-options');
    if (!bodyHtml && !hero) {
        band.classList.remove('open');
        band.innerHTML = '';
        revealSelectedCard(false);   // the grid grew: the picked card is still where it was
        return;
    }
    const pic = hero
        ? `<div class="cr-hero">${iconImg(hero.src)}<span class="cr-hero-art">${GLYPHS[hero.glyph] || ''}</span></div>`
        : '';
    if (side) {
        band.innerHTML = `<div class="cr-band-head"><div class="cr-band-title">${title}</div>`
            + (hero && hero.sub ? `<div class="cr-band-sub">${hero.sub}</div>` : '')
            + `<div class="cr-band-body">${bodyHtml || ''}</div></div>`
            + `<div class="cr-band-top">${pic}<div class="cr-band-side">${side}</div></div>`;
    } else {
        // The count's margin-top: auto stands it and the colours under it on the picture's bottom edge.
        const head = `<div class="cr-band-title${hero ? '' : ' small'}">${title}</div>`
            + (hero && hero.sub ? `<div class="cr-band-sub">${hero.sub}</div>` : '')
            + (hero && hero.meta ? `<div class="cr-band-meta">${hero.meta}</div>` : '');
        band.innerHTML = `<div class="cr-band-top">${pic}<div class="cr-band-main">${head}`
            + `<div class="cr-band-body">${bodyHtml || ''}</div></div></div>`;
    }
    band.classList.toggle('cr-band-sided', !!side);
    band.classList.add('open');

    // When the controls are more than the band holds they scroll under the heading: the picked
    // colour is scrolled to, and the cut edge fades while there is more below it.
    const body = band.querySelector('.cr-band-body');
    const tile = body.querySelector('.cr-tex.selected');
    if (tile) revealIn(body, tile, false);
    markBandScroll(body);
    body.addEventListener('scroll', () => markBandScroll(body), { passive: true });
    revealSelectedCard(false);       // the band's height moved the grid: keep the picked card in view
}

function markBandScroll(body) {
    body.classList.toggle('cr-scrolls', body.scrollTop + body.clientHeight < body.scrollHeight - 2);
}

/** Point the band's picture at another one (a colour picked): no rebuild, so nothing jumps. */
function setHeroIcon(src) {
    const hero = document.querySelector('#cr-options .cr-hero');
    if (!hero || !src) return;
    const img = hero.querySelector('img.cr-icon');
    if (img) { if (img.getAttribute('src') !== src) img.setAttribute('src', src); }
    else hero.insertAdjacentHTML('afterbegin', iconImg(src));
}

/**
 * The collection an item came in, in words: 'Base game', or the DLC's own name, tidied
 * ('mp_m_vinewood' → 'Vinewood', 'male_freemode_beach' → 'Beach'). GTA gives items no names; this is
 * the one fact about one there is. '' when the game did not name it (added-on clothing).
 */
function collectionOf(kind, slot, drawable) {
    const icons = maxVariations.icons;
    if (!icons || drawable < 0) return '';
    const names = kind === 'prop' ? (icons.props || {})[String(slot)] : (icons.components || {})[String(slot)];
    const name = names && names[drawable];
    if (!name) return '';
    const coll = name.replace(/_\d{3}$/, '');
    if (coll === 'base') return 'Base game';
    const words = coll.replace(/^(mp_[mf]_|male_freemode_|female_freemode_|male_|female_)/, '').replace(/_/g, ' ');
    return words.charAt(0).toUpperCase() + words.slice(1);
}

function coloursText(n) { return n === 1 ? '1 colour' : `${n} colours`; }

function sliderHtml(input, key, label, value, min, max) {
    return `<div class="cr-opt-row">
        <div class="cr-opt-label"><span>${label}</span><span class="cr-opt-val" id="cr-val-${input}-${key}">${value}</span></div>
        <input type="range" class="cr-range" min="${min}" max="${max}" value="${value}" data-input="${input}" data-key="${key}">
    </div>`;
}

/**
 * `palette` is already in display order; `count` is how many palette INDICES
 * the game says exist, so the cap is applied per entry rather than by slicing
 * the list — after sorting, position and index are no longer the same thing.
 */
function swatchGridHtml(target, palette, count, current) {
    let html = `<div class="cr-swatches" data-target="${target}">`;
    for (let i = 0; i < palette.length; i++) {
        const e = palette[i];
        if (e.index >= count) continue;
        html += `<button class="cr-swatch${current === e.index ? ' selected' : ''}" style="background:${e.css}"
            data-action="swatch" data-target="${target}" data-value="${e.index}" title="${e.index}"
            aria-label="Colour ${e.index}" aria-pressed="${current === e.index}"></button>`;
    }
    return html + '</div>';
}

/**
 * The colour chips. `iconFor(i)` gives colour i's picture, or null: a chip with one is a fixed-size
 * tile (so the panel is the same height whether the pictures load or not) that shows its number
 * until the picture arrives, and for good if it never does.
 */
const CHEVRON = '<svg viewBox="0 0 12 12" aria-hidden="true"><path d="M2.5 4.5 6 8l3.5-3.5" fill="none" stroke="currentColor"'
    + ' stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>';

function texRowHtml(count, current, iconFor) {
    // Two rows of pictures, then "+18 more" (option B): an item can have 26 colours, and all of them
    // at once would push the grid off the screen. Shown in full on a press ("Fewer" puts them back),
    // or when the colour worn is past the first rows (it must be on screen to be seen picked: no
    // "Fewer" then either).
    const folds = !!iconFor && count > TEX_SHOWN + 1 && current < TEX_SHOWN;
    const limit = (folds && !texExpanded) ? TEX_SHOWN : count;
    let html = '<div class="cr-texrow">';
    for (let i = 0; i < limit; i++) {
        const src = iconFor ? iconFor(i) : null;
        html += `<button class="cr-tex${src ? ' cr-tex-pic' : ''}${current === i ? ' selected' : ''}" data-action="tex" data-value="${i}"`
            + ` aria-label="Colour ${i}" aria-pressed="${current === i}">${iconImg(src)}<span class="cr-tex-num">${i}</span></button>`;
    }
    if (folds) {
        html += texExpanded
            ? `<button class="cr-tex cr-tex-more" data-action="texmore" aria-expanded="true">Fewer${CHEVRON}</button>`
            : `<button class="cr-tex cr-tex-more" data-action="texmore" aria-expanded="false"`
              + ` aria-label="Show ${count - limit} more colours">+${count - limit} more${CHEVRON}</button>`;
    }
    return html + '</div>';
}

const TEX_SHOWN = 11;        // colours shown before "+N more": two rows of six, the last one the button
let texExpanded = false;     // "+N more" pressed for the item showing; back to two rows for the next

// Stamped every time the panel is asked to render. Anything that has to wait
// on the game before it can draw checks this afterwards and stands down if a
// newer render has started — clicking quickly through watches otherwise lets
// an older reply paint over a newer selection.
let optionsGen = 0;

function renderOptions() {
    const gen = ++optionsGen;
    const cat = activeCategory;

    if (cat.kind === 'heritage') {
        // The parent the sub-tab picks, face and number, beside the blend (which is the three's).
        const hb = appearance.headBlend;
        const parent = hb[['mom', 'dad', 'grandparent'][activeSubtab]];
        setOptions(`${['Mother', 'Father', 'Grandparent'][activeSubtab]} ${parent}`,
            `<div class="cr-opt-label"><span>Blend</span></div>`
            + sliderHtml('blend', 'faceWeight', 'Face Mix', Math.round(hb.faceWeight * 100), 0, 100)
            + sliderHtml('blend', 'skinWeight', 'Skin Mix', Math.round(hb.skinWeight * 100), 0, 100)
            + sliderHtml('blend', 'thirdWeight', 'Grandparent Mix', Math.round(hb.thirdWeight * 100), 0, 100)
            + `<div class="cr-opt-hint">Face and skin blend mother &rarr; father; the third slider mixes the grandparent in.</div>`,
            { src: headIconOf(parent), glyph: 'face' });
        return;
    }

    if (cat.kind === 'features') {
        if (!activeFeatureGroup) { setOptions(null, null); return; }
        const g = activeFeatureGroup;
        let pad = '';
        if (g.y) {
            // The 2-axis pad, drawn as a tic-tac-toe grid of light: four lines
            // with round caps that overshoot their crossings, no box around
            // them. SVG rather than CSS borders because the caps and the
            // overshoot are the whole look. Dot position is written by
            // updatePad() after mount.
            pad = `<div class="cr-pad-wrap">
                <div class="cr-pad" id="cr-pad" data-x="${g.x.idx}" data-y="${g.y.idx}">
                    <svg class="cr-pad-grid" viewBox="0 0 100 100" aria-hidden="true">
                        <line x1="33.3" y1="4" x2="33.3" y2="96"/>
                        <line x1="66.7" y1="4" x2="66.7" y2="96"/>
                        <line x1="4" y1="33.3" x2="96" y2="33.3"/>
                        <line x1="4" y1="66.7" x2="96" y2="66.7"/>
                    </svg>
                    <span class="cr-pad-axis cr-pad-n">${g.y.pos}</span>
                    <span class="cr-pad-axis cr-pad-s">${g.y.neg}</span>
                    <span class="cr-pad-axis cr-pad-w">${g.x.neg}</span>
                    <span class="cr-pad-axis cr-pad-e">${g.x.pos}</span>
                    <div class="cr-pad-dot" id="cr-pad-dot"></div>
                </div>
            </div>
            <div class="cr-opt-hint">Drag the point &middot; double-click to reset</div>`;
        }
        let sliders = sliderHtml('fine', String(g.x.idx), g.x.label,
            Math.round(featureShown(g.x.idx) * 100), -100, 100);
        if (g.y) {
            sliders += sliderHtml('fine', String(g.y.idx), g.y.label,
                Math.round(featureShown(g.y.idx) * 100), -100, 100);
        }
        // The band is wide: the pad and its two sliders side by side, not stacked.
        setOptions(g.label, pad
            ? `<div class="cr-band-cols"><div class="cr-band-col">${pad}</div><div class="cr-band-col">${sliders}</div></div>`
            : sliders);
        if (g.y) updatePad();
        return;
    }

    if (cat.kind === 'hair' && activeSubtab === HAIR_FADE_TAB) {
        // No picture and nothing to set: the band only says which fade it is and where it shows.
        const i = wornFadeIndex(), f = i >= 0 ? fadeAt(i) : null;
        if (!f) { setOptions(null, null); return; }
        setOptions(`Fade ${i + 1}`, `<div class="cr-opt-hint">${escapeHtml(f.from)} &middot; drawn on the scalp, under the`
            + ` hairstyle. It shows best with a short one.</div>`);
        return;
    }

    if (cat.kind === 'hair') {
        const hair = appearance.hair;
        const hairPal = paletteFor('hair');
        const maxColor = (maxVariations.hair && maxVariations.hair.maxColor) || hairPal.length;
        // ASK FIRST, DRAW ONCE. How many textures a style has is only known
        // after a round-trip to the game, and drawing the band before the
        // answer arrives meant drawing it twice at two different heights. The
        // grid starts where the band ends, so the second one shunted every
        // card under it — a flicker on each new selection.
        nuiCallback('getMaxTexture', { type: 'hair', id: 2, drawable: hair.style }).then(resp => {
            if (gen !== optionsGen) return;
            const count = (resp && resp.maxTexture != null) ? resp.maxTexture : 0;
            // One texture is no choice at all. Its small pictures sit at the end of the heading's line;
            // the colours stand beside the big picture, Colour over Highlight, so the hairstyles below
            // keep their rows.
            const tex = count > 1 ? texRowHtml(count, hair.texture, i => iconOf('component', 2, hair.style, i)) : '';
            setOptions(`Hair ${hair.style}`, tex,
                { src: iconOf('component', 2, hair.style, hair.texture), glyph: 'hair',
                  sub: collectionOf('component', 2, hair.style) },
                `<div class="cr-band-colours"><div class="cr-opt-label"><span>Colour</span></div>${swatchGridHtml('hairColor', hairPal, maxColor, hair.color)}</div>`
                + `<div class="cr-band-colours"><div class="cr-opt-label"><span>Highlight</span></div>${swatchGridHtml('hairHighlight', hairPal, maxColor, hair.highlight)}</div>`);
        });
        return;
    }

    if (cat.kind === 'overlays') {
        const key = activeOverlayKey();
        const o = appearance.overlays[key];
        if (o.opacity === 0) { setOptions(null, null); return; }   // "None" selected — nothing to tune
        const label = activeCategory.overlays[activeSubtab].label;
        let body = sliderHtml('opacity', key, 'Opacity', Math.round(o.opacity * 100), 0, 100);
        const pal = OVERLAY_PALETTE[key];
        if (pal) {
            const palette = paletteFor(pal);
            body += `<div class="cr-band-cols">`
                + `<div class="cr-band-col"><div class="cr-opt-label"><span>Colour</span></div>${swatchGridHtml('ovColor', palette, palette.length, o.color)}</div>`
                + `<div class="cr-band-col"><div class="cr-opt-label"><span>Secondary</span></div>${swatchGridHtml('ovColor2', palette, palette.length, o.color2)}</div>`
                + `</div>`;
        }
        setOptions(`${label} ${o.type}`, body);   // its number here, as the band's other headings
        return;
    }

    if (cat.kind === 'tattoos') {
        // NO BAND: a tattoo has no colours to pick, and its big picture says nothing the card and the
        // ped do not. It shows only to say why a tattoo would not go on.
        if (!tattooFull) { setOptions(null, null); return; }
        setOptions(`${TATTOO_MAX} tattoos`,
            `<div class="cr-opt-hint cr-opt-warn">That is the most one character can have. Take one off to put another on.</div>`);
        return;
    }

    if (cat.kind === 'outfits') { renderOutfitBand(); return; }

    if (cat.kind === 'component' || cat.kind === 'prop') {
        const isProp = cat.kind === 'prop';
        const slot = isProp ? appearance.props[String(cat.prop)] : appearance.components[String(cat.comp)];
        if (isProp && slot.drawable === -1) { setOptions(null, null); return; }

        // Ask first, draw once — see the hair branch above. The previous
        // panel stays on screen for the round-trip, which reads as steady;
        // drawing an empty shell in its place and filling it a frame later is
        // what jumped.
        nuiCallback('getMaxTexture', {
            type: isProp ? 'prop' : 'component',
            id: isProp ? cat.prop : cat.comp,
            drawable: slot.drawable,
        }).then(resp => {
            if (gen !== optionsGen) return;
            const count = (resp && resp.maxTexture != null) ? resp.maxTexture : 0;
            const kind = isProp ? 'prop' : 'component', id = isProp ? cat.prop : cat.comp;
            // The item worn, big, with its colours. One colour is nothing to choose: the picture and
            // its count only, no single dead tile.
            setOptions(`${cat.one || cat.label} ${slot.drawable}`,
                count > 1 ? texRowHtml(count, slot.texture, i => iconOf(kind, id, slot.drawable, i)) : '',
                { src: iconOf(kind, id, slot.drawable, slot.texture), glyph: cat.glyph,
                  sub: collectionOf(kind, id, slot.drawable), meta: count > 0 ? coloursText(count) : '' });
        });
        return;
    }

    setOptions(null, null);   // eyes and anything else without options
}

// ========================================
// OPTION INTERACTIONS
// ========================================

function onTexClick(el) {
    const value = Number(el.dataset.value);
    const cat = activeCategory;
    let worn;
    if (cat.kind === 'hair') { appearance.hair.texture = value; worn = appearance.hair.style; }
    else if (cat.kind === 'component') { const c = appearance.components[String(cat.comp)]; c.texture = value; worn = c.drawable; dressAgain(); }
    else if (cat.kind === 'prop') { const p = appearance.props[String(cat.prop)]; p.texture = value; worn = p.drawable; dressAgain(); }
    else return;
    el.parentElement.querySelectorAll('.cr-tex').forEach(t => {
        const on = Number(t.dataset.value) === value;
        t.classList.toggle('selected', on);
        if (t.dataset.action === 'tex') t.setAttribute('aria-pressed', on ? 'true' : 'false');
    });
    setCardIcon(worn, value);   // its card shows the colour picked
    const s = iconSlotOf(cat);
    setHeroIcon(s && iconOf(s.kind, s.slot, worn, value));   // and so does the band's picture
    schedulePreview();
}

function onSwatchClick(el) {
    const value = Number(el.dataset.value);
    const target = el.dataset.target;
    if (target === 'hairColor') appearance.hair.color = value;
    else if (target === 'hairHighlight') appearance.hair.highlight = value;
    else if (target === 'ovColor') appearance.overlays[activeOverlayKey()].color = value;
    else if (target === 'ovColor2') appearance.overlays[activeOverlayKey()].color2 = value;
    else return;
    el.parentElement.querySelectorAll('.cr-swatch').forEach(s => {
        const on = Number(s.dataset.value) === value;
        s.classList.toggle('selected', on);
        s.setAttribute('aria-pressed', on ? 'true' : 'false');
    });
    schedulePreview();
}

function onBlendInput(el) {
    const v = Number(el.value);
    appearance.headBlend[el.dataset.key] = v / 100;
    const label = $('cr-val-blend-' + el.dataset.key);
    if (label) label.textContent = v;
    schedulePreview();
}

function onOpacityInput(el) {
    const key = el.dataset.key;
    const o = appearance.overlays[key];
    o.opacity = Number(el.value) / 100;
    const label = $('cr-val-opacity-' + key);
    if (label) label.textContent = el.value;
    schedulePartPreview('ov' + key, {
        kind: 'overlay', key: key,
        type: o.type, opacity: o.opacity, color: o.color, color2: o.color2,
    });
    // Dragging opacity to 0 flips the grid's selection to None — but repainting
    // mid-drag would yank the slider out from under the pointer; leave the grid
    // until the next render pass touches it.
}

// A face feature as the pad and its sliders show it (featureSign: GTA's +1 runs
// against the labels), and back.
function featureShown(idx) { return (appearance.faceFeatures[idx] || 0) * featureSign(idx); }
function setFeatureShown(idx, v) { appearance.faceFeatures[idx] = v * featureSign(idx); }

function onFineInput(el) {
    const idx = Number(el.dataset.key);
    setFeatureShown(idx, Number(el.value) / 100);
    const label = $('cr-val-fine-' + el.dataset.key);
    if (label) label.textContent = el.value;
    updatePad();
    schedulePartPreview('ff' + idx, { kind: 'feature', idx: idx, value: appearance.faceFeatures[idx] });
}

// ========================================
// THE FEATURE PAD
//
// A square mapped to [-1, +1] on both axes; the dot mirrors the two feature
// values and dragging writes them back. Screen Y grows downward, feature "up"
// is positive — hence the flip.
// ========================================

let padDragging = false;

function updatePad() {
    const pad = $('cr-pad');
    const dot = $('cr-pad-dot');
    if (!pad || !dot) return;
    const gx = Number(pad.dataset.x), gy = Number(pad.dataset.y);
    const vx = featureShown(gx), vy = featureShown(gy);
    dot.style.left = ((vx + 1) / 2 * 100) + '%';
    dot.style.top = ((1 - (vy + 1) / 2) * 100) + '%';
}

function padApply(pad, clientX, clientY) {
    const r = pad.getBoundingClientRect();
    const nx = clamp((clientX - r.left) / r.width * 2 - 1, -1, 1);
    const ny = clamp(1 - (clientY - r.top) / r.height * 2, -1, 1);
    const gx = Number(pad.dataset.x), gy = Number(pad.dataset.y);
    setFeatureShown(gx, Math.round(nx * 100) / 100);
    setFeatureShown(gy, Math.round(ny * 100) / 100);
    updatePad();
    // Keep the fine sliders honest while the pad drives.
    const panel = $('cr-options');
    panel.querySelectorAll('input[data-input="fine"]').forEach(s => {
        const idx = Number(s.dataset.key);
        const v = Math.round(featureShown(idx) * 100);
        s.value = v;
        const label = $('cr-val-fine-' + s.dataset.key);
        if (label) label.textContent = v;
    });
    // The hottest path in the creator — two features, streamed every frame.
    schedulePartPreview('ff' + gx, { kind: 'feature', idx: gx, value: appearance.faceFeatures[gx] });
    schedulePartPreview('ff' + gy, { kind: 'feature', idx: gy, value: appearance.faceFeatures[gy] });
}

function bindPadEvents(root) {
    root.addEventListener('pointerdown', (e) => {
        const pad = e.target.closest('.cr-pad');
        if (!pad) return;
        padDragging = true;
        pad.setPointerCapture(e.pointerId);
        padApply(pad, e.clientX, e.clientY);
    });
    root.addEventListener('pointermove', (e) => {
        if (!padDragging) return;
        const pad = $('cr-pad');
        if (pad) padApply(pad, e.clientX, e.clientY);
    });
    root.addEventListener('pointerup', () => { padDragging = false; });
    root.addEventListener('dblclick', (e) => {
        const pad = e.target.closest('.cr-pad');
        if (!pad) return;
        appearance.faceFeatures[Number(pad.dataset.x)] = 0;
        appearance.faceFeatures[Number(pad.dataset.y)] = 0;
        renderOptions();   // re-sync pad + sliders in one pass
        schedulePreview();
    });
}

// ========================================
// CAMERA ORBIT
//
// The empty centre of the screen is a capture layer: drag to swing the camera
// around the ped — horizontally for bearing, vertically for height. The PED
// never turns; the rig does, which is what lets a framing change and a drag be
// the same continuous movement. Deltas accumulate and flush on a short timer so
// a fast wipe doesn't fire a hundred NUI callbacks (Lua clamps per call too).
// ========================================

let stageBtn = -1;        // 0 = left held, 2 = right held, -1 = idle
let stageLastX = 0;
let stageLastY = 0;
let inPan = 0, inOrbitX = 0, inOrbitY = 0, inZoom = 0;
let inputTimer = null;
let wheelHintTimer = null;

/** Light up whichever part of the mouse legend is being used. */
function setMouseHint(part, on) {
    const el = document.querySelector('.cr-m-' + part);
    if (el) el.classList.toggle('on', !!on);
}

function flushCamInput() {
    inputTimer = null;
    if (inPan || inOrbitX || inOrbitY || inZoom) {
        nuiCallback('camInput', { pan: inPan, orbitX: inOrbitX, orbitY: inOrbitY, zoom: inZoom });
        inPan = 0; inOrbitX = 0; inOrbitY = 0; inZoom = 0;
    }
}

function queueCamInput() {
    if (!inputTimer) inputTimer = setTimeout(flushCamInput, 32);
}

function bindStageEvents(root) {
    const stage = $('cr-stage');

    stage.addEventListener('pointerdown', (e) => {
        if (e.button !== 0 && e.button !== 2) return;
        stageBtn = e.button;
        stageLastX = e.clientX;
        stageLastY = e.clientY;
        stage.setPointerCapture(e.pointerId);
        stage.classList.add('dragging');
        setMouseHint(stageBtn === 0 ? 'lmb' : 'rmb', true);
    });

    stage.addEventListener('pointermove', (e) => {
        if (stageBtn < 0) return;
        const dx = e.clientX - stageLastX;
        const dy = e.clientY - stageLastY;
        stageLastX = e.clientX;
        stageLastY = e.clientY;

        if (stageBtn === 0) {
            inPan += dy;                 // left: slide the shot up and down the body
        } else {
            inOrbitX += dx;              // right: swing around it
            inOrbitY += dy;
        }
        queueCamInput();
    });

    const end = () => {
        if (stageBtn >= 0) setMouseHint(stageBtn === 0 ? 'lmb' : 'rmb', false);
        stageBtn = -1;
        stage.classList.remove('dragging');
    };
    stage.addEventListener('pointerup', end);
    stage.addEventListener('pointercancel', end);

    // Right-drag would otherwise raise CEF's context menu mid-orbit.
    stage.addEventListener('contextmenu', (e) => e.preventDefault());

    // WHEEL LIVES ON THE ROOT, NOT THE STAGE. Pointer capture routes pointer
    // events to the stage but not wheel events, so a drag that wanders over
    // the card list would otherwise scroll the list instead of zooming. The
    // guard is what keeps both behaviours: with no button held this does
    // nothing at all and the card list scrolls exactly as before.
    root.addEventListener('wheel', (e) => {
        if (stageBtn < 0) return;
        e.preventDefault();
        inZoom += (e.deltaY > 0 ? 1 : -1);
        setMouseHint('wheel', true);
        if (wheelHintTimer) clearTimeout(wheelHintTimer);
        wheelHintTimer = setTimeout(() => setMouseHint('wheel', false), 220);
        queueCamInput();
    }, { passive: false });
}

// ========================================
// SAVE / CANCEL
// ========================================

function saveAppearance() {
    disarmCancel();
    if (store) {
        if (store.busy) return;
        store.busy = true;
        store.why = '';
        markStorePrice();
    }
    nuiCallback('saveAppearance', { appearance: collectAppearance() });
}

/** A store's Save says the price of what changed: "Pay $120", or Save while nothing costs anything. */
function markStorePrice() {
    const btn = $('cr-save');
    if (!btn) return;
    if (!store) { btn.textContent = 'Save'; btn.title = ''; return; }
    const total = storePrice(storeChanges(store.from, collectAppearance(), store.only), store.prices);
    btn.textContent = store.busy ? 'Paying…' : store.why ? store.why : total > 0 ? `Pay $${total.toLocaleString('en-US')}` : 'Save';
    btn.classList.toggle('refused', !!store.why && !store.busy);
}

// The store said no (not enough money, too far away): the editor stays open, the reason on Save until the next change.
NuiRouter.register('creatorSaveRefused', (d) => {
    if (!store) return;
    store.busy = false;
    store.why = typeof d.why === 'string' && d.why ? d.why : 'Not saved';
    markStorePrice();
});

// Cancel is destructive (every tweak since open is lost), so it arms first:
// one press turns the button into "DISCARD?", a second within 3s confirms.
// Cheaper than a modal, still one honest mistake away from safe.
function attemptCancel() {
    if (cancelArmed) {
        disarmCancel();
        nuiCallback('cancelCreator', {});
        return;
    }
    const btn = $('cr-cancel');
    btn.classList.add('armed');
    btn.textContent = 'Discard?';
    const padB = $('cr-pad-b');      // the pad's B says it too: a second press discards
    if (padB) padB.textContent = 'Discard?';
    cancelArmed = setTimeout(disarmCancel, 3000);
}

function disarmCancel() {
    if (cancelArmed) clearTimeout(cancelArmed);
    cancelArmed = null;
    const btn = $('cr-cancel');
    if (btn) {
        btn.classList.remove('armed');
        btn.textContent = isNew ? 'Skip' : 'Cancel';
    }
    const hint = $('cr-esc-hint');   // the legend names what Esc does: the same button
    if (hint) hint.textContent = isNew ? 'Skip' : 'Cancel';
    const padB = $('cr-pad-b');      // and on a pad, what B does
    if (padB) padB.textContent = isNew ? 'Skip' : 'Cancel';
}

// ========================================
// DELEGATED ACTIONS
//
// The documented reference shape (docs/nui-architecture.md): listeners on the
// #creator root, parameters as data-*, dispatch through Maps so a lookup can't
// be shadowed by Object.prototype names. Top-level DOM reads are safe — the
// module script sits at the end of <body>.
// ========================================

(function bindCreatorActions() {
    const root = document.getElementById('creator');

    const CLICK = new Map([
        ['cluster',  el => selectCluster(el.dataset.cluster)],
        ['category', el => selectCategory(el.dataset.cat)],
        ['subtab',   el => selectSubtab(Number(el.dataset.idx))],
        ['card',     el => onCardClick(el)],
        ['tex',      el => onTexClick(el)],
        ['texmore',  () => { texExpanded = !texExpanded; renderOptions(); }],
        ['swatch',   el => onSwatchClick(el)],
        ['undress',  () => toggleUndress()],
        ['outfitSave',   () => saveOutfit()],
        ['outfitUpdate', el => updateOutfit(Number(el.dataset.value))],
        ['outfitRename', el => renameOutfit(Number(el.dataset.value))],
        ['outfitDelete', el => deleteOutfit(el)],
        ['save',     () => saveAppearance()],
        ['cancel',   () => attemptCancel()],
    ]);

    const INPUT = new Map([
        ['blend',   el => onBlendInput(el)],
        ['opacity', el => onOpacityInput(el)],
        ['fine',    el => onFineInput(el)],
    ]);

    root.addEventListener('click', (e) => {
        const el = e.target.closest('[data-action]');
        if (!el) return;
        const fn = CLICK.get(el.dataset.action);
        if (fn) fn(el);
    });

    root.addEventListener('input', (e) => {
        const el = e.target.closest('[data-input]');
        if (!el) return;
        const fn = INPUT.get(el.dataset.input);
        if (fn) fn(el);
    });

    $('cr-grid').addEventListener('scroll', onGridScroll);
    // Clothing pictures: a card or colour chip shows its picture once it has loaded (its glyph and
    // number step aside), and one that has none keeps them. Image load and error do not bubble:
    // caught on the way down, as the emote menu catches its videos'.
    ['cr-grid', 'cr-options'].forEach(id => {
        const el = $(id);
        el.addEventListener('load', (e) => {
            const img = e.target;
            if (img.classList && img.classList.contains('cr-icon')) img.parentElement.classList.add('has-icon');
        }, true);
        el.addEventListener('error', (e) => {
            const img = e.target;
            if (!(img.classList && img.classList.contains('cr-icon'))) return;
            img.parentElement.classList.remove('has-icon');
            img.remove();
        }, true);
    });
    bindPadEvents(root);
    bindStageEvents(root);
})();

// ========================================
// CONTROLLER
//
// A pad gets a mouse: the shared circle (pad-cursor.js), the inventory's, the shops' and /whip's. The left
// stick moves it, slowing over anything it can press, and A presses what is under it with the mouse's own
// click, so there is one path for both. The D-pad jumps it to the nearest control that way. Sliders and
// the face's shape pad are dragged: A held on one, the circle moves it (it slows over it, for a fine
// touch); left / right on the D-pad over a slider nudge it a step. LB / RB step through the categories
// (all of them, group to group). X is Undress. Y puts the circle on Save and A then saves: never by
// accident, because Save hands a new character to the world. B is Cancel, as Esc is (twice: the first
// press only asks). The right stick scrolls the cards when the circle is on them and turns round the
// character anywhere else (up and down the body too); the triggers zoom: the mouse's own camInput. An
// outfit's name box opens whip's keyboard. The buttons are listed in the panel's foot, where the mouse's
// are on a keyboard, and A's and the right stick's words follow what is under the circle.
// ========================================

const PAD_ORBIT = 520;          // the right stick at a full push turns the camera as a mouse drag of this many px a second
const PAD_HEIGHT = 320;         // up and down the body, the same
const PAD_ZOOM = 6;             // a trigger pulled all the way: this many mouse-wheel steps a second
const PAD_SLIDE_FAST = 5;       // a slider nudged with the D-pad and held: its step grows from 1 to this
const PAD_PAN = 1000;           // what pad-cursor.js hands pan() at a full push of the right stick, px a second (its PAN)

const PAD_TARGETS = '.cr-group, .cr-tab, .cr-subtab, .cr-tex, .cr-swatch, .cr-range, .cr-pad, .cr-input, .cr-obtn, .cr-card, .cr-dress, .cr-btn';

const ctl = {
    stick: { lt: 0, rt: 0 },    // the triggers: the camera's zoom
    raf: 0, last: 0,
    drag: null,                 // A held on a slider or the shape pad: what the circle drags
    dragAt: null,               // where the circle was when the drag was last applied
    slideAt: 0, slideRun: 0,    // a slider's last nudge and how many in a row
    legendQueued: false,
};

const cursor = createPadCursor({
    name: 'creator',
    root: () => $('creator'),
    shown: () => creatorOpen && !padKeyboardOpen(),
    targets: PAD_TARGETS,
    // First seen on the card worn, else the first card, else the category's tab.
    start: () => {
        const grid = $('cr-grid');
        return grid.querySelector('.cr-card.selected') || grid.querySelector('.cr-card')
            || document.querySelector('#cr-rail .cr-tab.active');
    },
    // A on a slider or the shape pad: held, the circle drags it (the mouse's pointer events do not come from
    // a pad, and a slider is not typed into).
    press: (n) => {
        const el = n.closest('.cr-range, .cr-pad');
        if (!el) return false;
        ctl.drag = el;
        ctl.dragAt = null;
        dragTo();
        ctlRun();
        return true;
    },
    label: (field) => (field.id === 'cr-outfit-name' ? 'Outfit name' : null),
    // The right stick off the cards: round the character, and up and down it.
    pan: (dx, dy) => {
        inOrbitX += -dx / PAD_PAN * PAD_ORBIT;
        inPan += dy / PAD_PAN * PAD_HEIGHT;
        queueCamInput();
    },
});

/** The slider or shape pad being dragged, to where the circle is now: a slider by its own input event
 *  (the mouse's path), the pad as a pointer on it would. */
function dragTo() {
    const el = ctl.drag;
    if (!el || !el.isConnected) { ctl.drag = null; return; }
    const p = cursor.pos();
    if (ctl.dragAt && ctl.dragAt.x === p.x && ctl.dragAt.y === p.y) return;
    ctl.dragAt = p;
    if (el.classList.contains('cr-pad')) { padApply(el, p.x, p.y); return; }
    const r = el.getBoundingClientRect();
    const min = Number(el.min), max = Number(el.max);
    const v = Math.round(min + clamp((p.x - r.left) / (r.width || 1), 0, 1) * (max - min));
    if (String(v) === el.value) return;
    el.value = String(v);
    el.dispatchEvent(new Event('input', { bubbles: true }));
}

/** Move a slider one step (more when held), through its own input event: the mouse's path. */
function ctlSlide(el, sign) {
    const now = performance.now();
    ctl.slideRun = now - ctl.slideAt < 200 ? ctl.slideRun + 1 : 0;
    ctl.slideAt = now;
    const step = Math.min(PAD_SLIDE_FAST, 1 + Math.floor(ctl.slideRun / 3));
    const v = clamp(Number(el.value) + sign * step, Number(el.min), Number(el.max));
    if (String(v) === el.value) return;
    el.value = String(v);
    el.dispatchEvent(new Event('input', { bubbles: true }));
}

/** LB / RB: the category before or after, across the groups. The circle stays where it is (the tabs
 *  are where they were; on the cards it is over the new category's); what is under it is ringed again. */
function ctlCategory(step) {
    if (!activeCategory) return;
    const i = shownCats.indexOf(activeCategory);
    selectCategory(shownCats[(i + step + shownCats.length) % shownCats.length].id);
    requestAnimationFrame(() => cursor.refresh());
}

function ctlNav(nav) {
    if (!creatorOpen) return;
    const over = cursor.on() ? cursor.over() : null;
    // Over a slider, left and right nudge it a step; the circle stays.
    if (over && over.classList.contains('cr-range') && (nav === 'left' || nav === 'right')) {
        ctlSlide(over, nav === 'right' ? 1 : -1);
        return;
    }
    // Down from the last row of cards drawn: the next rows are drawn first (they come as the grid scrolls).
    if (nav === 'down' && over && $('cr-grid').contains(over) && gridRendered < gridCards.length) appendGridChunk();
    // X is Undress here (the cursor's X is a right click, which nothing in the creator has).
    if (nav === 'buttonX') {
        const dress = document.querySelector('#cr-undress .cr-dress');
        if (dress) dress.click();
        return;
    }
    if (cursor.nav(nav)) { ctlLegend(); return; }
    if (nav === 'back') { cursor.letGo(); attemptCancel(); return; }
    if (nav === 'tabPrev') { ctlCategory(-1); return; }
    if (nav === 'tabNext') { ctlCategory(1); return; }
    if (nav === 'buttonY') { cursor.moveTo($('cr-save')); ctlLegend(); return; }
    // 'select' is A's press, which the cursor has from navAnalog's `a`, with its release.
}

// ---- the sticks and triggers ----

/** The left stick, A and the right stick go to the circle; the triggers and a drag are the creator's. */
function ctlAnalog(a) {
    cursor.analog(a);
    if (ctl.drag && a.a !== true) ctl.drag = null;   // A let go: the drag is over
    ctl.stick = { lt: +a.lt || 0, rt: +a.rt || 0 };
    ctlRun();
    ctlLegend();
}

function ctlRun() {
    if (ctl.raf || !creatorOpen) return;
    if (!(ctl.stick.lt || ctl.stick.rt) && !ctl.drag) return;
    ctl.last = performance.now();
    ctl.raf = requestAnimationFrame(ctlFrame);
}

/** The triggers' zoom, folded into the mouse's camInput batch, and a drag following the circle. Runs
 *  only while a trigger is pulled or A holds a slider or the pad. */
function ctlFrame(now) {
    ctl.raf = 0;
    if (!creatorOpen) return;
    const dt = Math.min(0.05, Math.max(0, (now - ctl.last) / 1000));
    ctl.last = now;
    const s = ctl.stick;
    if (s.lt || s.rt) {
        inZoom += (s.lt - s.rt) * PAD_ZOOM * dt;   // RT in, LT out (the wheel down is out)
        queueCamInput();
    }
    if (ctl.drag) dragTo();
    if (s.lt || s.rt || ctl.drag) ctl.raf = requestAnimationFrame(ctlFrame);
}

// ---- the buttons, in the panel's foot ----

const PAD_LEGEND = [
    { b: ['ls'], t: 'Move' },
    { b: ['a'], t: 'Choose', label: 'cr-pad-a' },
    { b: ['lb', 'rb'], t: 'Category' },
    { b: ['rs'], t: 'Camera', label: 'cr-pad-rs' },
    { b: ['lt', 'rt'], t: 'Zoom' },
    { b: ['x'], t: 'Undress', id: 'cr-pad-x' },
    { b: ['y'], t: 'Save' },
    { b: ['b'], t: 'Cancel', label: 'cr-pad-b' },
];

/** A's and the right stick's words, for what is under the circle: a slider or the pad is dragged, the
 *  name box typed into; over the cards (or the band's colours when they scroll) the right stick scrolls
 *  them. Once a frame at most. */
function ctlLegend() {
    if (ctl.legendQueued) return;
    ctl.legendQueued = true;
    requestAnimationFrame(() => {
        ctl.legendQueued = false;
        const over = cursor.on() ? cursor.over() : null;
        const at = cursor.at();
        const a = ctl.drag || (over && over.matches('.cr-range, .cr-pad')) ? 'Drag'
            : over && over.matches('.cr-input') ? 'Type' : 'Choose';
        const list = at && at.closest('#cr-grid, .cr-band-body');
        const rs = list && list.scrollHeight > list.clientHeight ? 'Scroll' : 'Camera';
        const aEl = $('cr-pad-a'), rsEl = $('cr-pad-rs');
        if (aEl && aEl.textContent !== a) aEl.textContent = a;
        if (rsEl && rsEl.textContent !== rs) rsEl.textContent = rs;
    });
}

(function buildPadLegend() {
    const box = $('cr-pad-hints');
    if (!box) return;
    for (const h of PAD_LEGEND) {
        const item = document.createElement('span');
        item.className = 'cr-hint';
        if (h.id) item.id = h.id;
        for (const name of h.b) {
            const img = padGlyph(name, 'cr-pad-glyph');
            if (img) item.appendChild(img);
        }
        const word = document.createElement('span');
        word.textContent = h.t;
        if (h.label) word.id = h.label;
        item.appendChild(word);
        box.appendChild(item);
    }
    // A redraw under a still circle takes the ring with the old element: ring what is there now.
    new MutationObserver(() => {
        if (creatorOpen && cursor.on() && !ctl.markQueued) {
            ctl.markQueued = true;
            requestAnimationFrame(() => { ctl.markQueued = false; cursor.refresh(); ctlLegend(); });
        }
    }).observe(document.querySelector('#creator .cr-scale'), { childList: true, subtree: true });
})();

// ========================================
// OPEN / CLOSE
// ========================================

NuiRouter.register('openCreator', (d) => {
    appearance = normalizeAppearance(d.appearance || {});
    maxVariations = d.maxVariations || {};
    pictureSets = null;
    // What the player came in wearing stays on offer, picture or not (hasPicture's "always kept").
    openedWith = { components: {}, props: {} };
    ['components', 'props'].forEach(group => Object.keys(appearance[group] || {}).forEach(slot => {
        openedWith[group][slot] = appearance[group][slot].drawable;
    }));
    isNew = !!d.isNew;
    outfits = normalizeOutfits(d.outfits);
    outfitMax = Number(d.outfitMax) > 0 ? Number(d.outfitMax) : 20;
    outfitLast = null;
    outfitWhy = '';
    outfitBusy = false;
    // The heading: whose look this is when it is not the player's own (client/appearance.lua EditLook).
    const titleEl = document.querySelector('#creator .cr-title-name');
    const subEl = document.querySelector('#creator .cr-title-sub');
    if (titleEl) titleEl.textContent = typeof d.title === 'string' && d.title ? d.title : 'Character Creator';
    if (subEl) subEl.textContent = typeof d.sub === 'string' && d.sub ? d.sub : 'Appearance';
    // A store's tabs and prices (client/appearance.lua EditAppearance), or every tab and a plain Save.
    const s = d.store && typeof d.store === 'object' ? d.store : null;
    const only = s && Array.isArray(s.only) && s.only.length ? new Set(s.only.map(String)) : null;
    store = s ? { only, prices: (s.prices && typeof s.prices === 'object') ? s.prices : {},
        from: collectAppearanceOf(appearance), busy: false, why: '' } : null;
    shownCats = CATEGORIES.filter(cat => storeAllows(only, cat));
    if (!shownCats.length) shownCats = CATEGORIES;
    shownClusters = CLUSTER_ORDER.filter(key => shownCats.some(cat => cat.cluster === key));
    markStorePrice();
    creatorOpen = true;
    currentCamPreset = 'torso';  // OpenCreator's Lua side starts on the torso preset
    activeCluster = shownCats[0].cluster;
    // The palettes arrive with maxVariations, so last session's sorted copy is
    // stale the moment a new one does.
    delete paletteCache.hair;
    delete paletteCache.makeup;
    disarmCancel();
    undressed = false;           // every open starts dressed
    cursor.hide();               // the circle comes back on the card worn, at the first push or press
    buildUndress();
    loadNames();                 // the first open only: kept after that
    buildRail();
    document.getElementById('creator').classList.add('open');
    selectCategory(shownCats[0].id);
    // Laid out first (display: block a frame ago), so the stage's box is real.
    requestAnimationFrame(() => requestAnimationFrame(reportStage));
});

// ========================================
// WHERE THE CHARACTER STANDS
//
// The camera points at the ped, so it stands in the middle of the screen — which
// is the panel's edge now that the panel is wide (option B). The page says where
// the open world is (the stage's centre, -1 at the left edge of the screen to 1
// at the right) and the camera slides sideways to stand the ped there
// (client/appearance.lua, creatorStage). Measured, not assumed: the panel's width
// on screen follows the resolution scale.
// ========================================

function reportStage() {
    if (!creatorOpen) return;
    const r = $('cr-stage').getBoundingClientRect();
    if (!r.width || !window.innerWidth) return;
    const x = ((r.left + r.right) / 2) / window.innerWidth * 2 - 1;
    nuiCallback('creatorStage', { x: Math.round(x * 1000) / 1000 });
}

window.addEventListener('resize', () => { if (creatorOpen) requestAnimationFrame(reportStage); });

// The picture list, when it came after the open (client/appearance.lua askPictures): the cards of a
// group that leaves unpictured items out are listed again if that group is showing.
NuiRouter.register('creatorPictures', (d) => {
    const icons = maxVariations.icons;
    if (!creatorOpen || !icons || !d || d.gender !== icons.gender) return;
    icons.pictures = d.pictures;
    pictureSets = null;
    if (activeCategory && ONLY_PICTURED.has(activeCategory.cluster)) renderGrid();
});

NuiRouter.register('closeCreator', () => {
    creatorOpen = false;
    if (ctl.raf) { cancelAnimationFrame(ctl.raf); ctl.raf = 0; }
    ctl.stick = { lt: 0, rt: 0 };
    ctl.drag = null;
    cursor.hide();
    disarmCancel();
    disarmOutfitDelete();
    store = null;
    markStorePrice();
    document.getElementById('creator').classList.remove('open');
    $('cr-grid').innerHTML = '';
    setOptions(null, null);
});

// Priority 0: while the creator is open every key belongs to it. Escape arms /
// confirms Cancel; everything else is consumed so game binds stay quiet. A pad
// drives it too (CONTROLLER above), with the sticks and triggers as numbers.
// Typing an outfit's name, Enter presses its button and Escape leaves the box. While whip's keyboard is
// up (a pad typing that name) the scope stands down, so the keyboard, under it in priority, has the pad.
NuiRouter.registerKeyScope({
    name: 'creator', priority: 0,
    isOpen: () => creatorOpen && !padKeyboardOpen(),
    onKey: (e) => {
        if (e.target && e.target.id === 'cr-outfit-name') {
            if (e.key === 'Enter') {
                const btn = document.querySelector('#cr-options [data-action="outfitSave"], #cr-options [data-action="outfitRename"]');
                if (btn && !btn.disabled) btn.click();
            } else if (e.key === 'Escape') {
                e.target.blur();
            }
            return;
        }
        if (e.key === 'Escape') attemptCancel();
    },
    onNav: ctlNav,
    analog: true,
    onAnalog: ctlAnalog,
});
