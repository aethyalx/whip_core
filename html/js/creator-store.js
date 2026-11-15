// The character editor in a store (client/appearance.lua EditAppearance): only some tabs, and a price on Save.
//
// What changed between the look the editor opened on and the one now, by tab, as shared/appearance_parts.lua
// counts it on the server (which charges): keep the two the same. A count per category id ('tops': 1, 'makeup': 2
// for two of its three overlays), and 'tattoos' for tattoos put on (taking one off is free). Taking off a hat,
// glasses or any other accessory is free too.

import { CATEGORIES } from './creator-data.js';

const EPS = 0.001;
const same = (a, b) => (typeof a === 'number' && typeof b === 'number') ? Math.abs(a - b) < EPS : a === b;
const slotSame = (a, b) => same((a || {}).drawable, (b || {}).drawable) && same((a || {}).texture, (b || {}).texture);
const overlaySame = (a, b) => ['type', 'opacity', 'color', 'color2'].every(k => same((a || {})[k] ?? 0, (b || {})[k] ?? 0));
const tattooKey = (t) => `${String(t.collection).toLowerCase()}|${String(t.overlay).toLowerCase()}`;

/** Is this tab offered? `only` is a Set of category ids and cluster names ('apparel'), or null for every tab. */
export function storeAllows(only, cat) {
    return !only || only.has(cat.id) || only.has(cat.cluster);
}

/** { [category id]: count, tattoos: count } of what differs from `from` in the tabs `only` offers. */
export function storeChanges(from, to, only) {
    const out = {};
    const add = (k, n) => { if (n > 0) out[k] = (out[k] || 0) + n; };
    for (const cat of CATEGORIES) {
        if (!storeAllows(only, cat)) continue;
        if (cat.kind === 'heritage') {
            const a = from.headBlend || {}, b = to.headBlend || {};
            add(cat.id, ['mom', 'dad', 'grandparent', 'faceWeight', 'skinWeight', 'thirdWeight'].some(k => !same(a[k], b[k])) ? 1 : 0);
        } else if (cat.kind === 'features') {
            const a = from.faceFeatures || [], b = to.faceFeatures || [];
            let diff = false;
            for (let i = 0; i < 20; i++) if (!same(a[i] ?? 0, b[i] ?? 0)) diff = true;
            add(cat.id, diff ? 1 : 0);
        } else if (cat.kind === 'eyes') {
            add(cat.id, same(from.eyeColor, to.eyeColor) ? 0 : 1);
        } else if (cat.kind === 'hair') {
            const a = from.hair || {}, b = to.hair || {};
            const fa = from.hairFade ? tattooKey(from.hairFade) : '', fb = to.hairFade ? tattooKey(to.hairFade) : '';
            add(cat.id, (['style', 'texture', 'color', 'highlight'].some(k => !same(a[k], b[k])) || fa !== fb) ? 1 : 0);
        } else if (cat.kind === 'overlays') {
            for (const o of cat.overlays) {
                add(cat.id, overlaySame((from.overlays || {})[o.key], (to.overlays || {})[o.key]) ? 0 : 1);
            }
        } else if (cat.kind === 'component') {
            const k = String(cat.comp);
            add(cat.id, slotSame((from.components || {})[k], (to.components || {})[k]) ? 0 : 1);
        } else if (cat.kind === 'prop') {
            const k = String(cat.prop), b = (to.props || {})[k] || {};
            add(cat.id, (b.drawable >= 0 && !slotSame((from.props || {})[k], b)) ? 1 : 0);
        } else if (cat.kind === 'tattoos' && out.tattoos === undefined) {
            const had = new Set((from.tattoos || []).map(tattooKey));
            out.tattoos = (to.tattoos || []).filter(t => !had.has(tattooKey(t))).length;
            if (!out.tattoos) delete out.tattoos;
        }
    }
    return out;
}

/** The price of `changes`: prices[category id], else prices[its cluster], else prices.default, each time. */
export function storePrice(changes, prices) {
    let total = 0;
    for (const [id, n] of Object.entries(changes)) {
        const cat = CATEGORIES.find(c => c.id === id);
        const each = prices[id] ?? (cat && prices[cat.cluster]) ?? prices.default ?? 0;
        total += Math.max(0, Number(each) || 0) * n;
    }
    return Math.round(total);
}
