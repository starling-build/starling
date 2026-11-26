// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Screen readers in the browser. The app sends its semantics snapshot (FlutterWeb/WebAccessibility.swift) as a
// JSON array of [flags, x, y, width, height, label, value, hint] in CSS pixels; this keeps one ARIA element per
// node, in reading order, in a transparent layer over the canvas that never takes the pointer. Keys stay with
// the canvas (or the IME textarea): the focused node is named through aria-activedescendant, and a reader's
// click on an element (NVDA Enter in browse mode, VoiceOver VO+Space) runs the node's tap in the app.
// Announcements go to two aria-live regions. Off until turned on: a visually hidden button first in the Tab
// order, ?a11y=1 in the address, or the choice remembered from a previous visit.

// The same bits as WebAccessibility.Flag.
const BUTTON = 1, TEXT_FIELD = 2, HEADER = 4, HAS_CHECKED = 8, CHECKED = 16, HAS_TOGGLED = 32, TOGGLED = 64;
const HAS_SELECTED = 128, SELECTED = 256, DISABLED = 512, FOCUSED = 1024, CAN_TAP = 2048;

const KEY = 'starling-a11y';
const HIDDEN = 'position:absolute;width:1px;height:1px;margin:-1px;padding:0;border:0;overflow:hidden;clip:rect(0 0 0 0);white-space:nowrap;';

/// The role and ARIA state of one node (exported for tests).
export function describe(flags) {
  const a = {};
  if (flags & TEXT_FIELD) { a.role = 'textbox'; a['aria-multiline'] = 'true'; }
  else if (flags & HAS_TOGGLED) { a.role = 'switch'; a['aria-checked'] = String(!!(flags & TOGGLED)); }
  else if (flags & HAS_CHECKED) { a.role = 'checkbox'; a['aria-checked'] = String(!!(flags & CHECKED)); }
  else if (flags & (BUTTON | CAN_TAP)) {
    a.role = 'button';
    // The framework marks every button selected or not; only a pressed one reads as a toggle ("Save, toggle
    // button, not pressed" on every plain button is noise).
    if ((flags & HAS_SELECTED) && (flags & SELECTED)) a['aria-pressed'] = 'true';
  } else if (flags & HEADER) { a.role = 'heading'; a['aria-level'] = '2'; }
  if (flags & DISABLED) a['aria-disabled'] = 'true';
  return a;
}

const ATTRS = ['role', 'aria-multiline', 'aria-checked', 'aria-pressed', 'aria-level', 'aria-disabled'];

export function createA11y({ canvas, ime, swift }) {
  const layer = document.createElement('div');
  layer.id = 'starling-a11y';
  layer.style.cssText = 'position:fixed;left:0;top:0;width:0;height:0;overflow:visible;pointer-events:none;opacity:0;';
  const polite = document.createElement('div');
  const assertive = document.createElement('div');
  for (const [region, level] of [[polite, 'polite'], [assertive, 'assertive']]) {
    region.setAttribute('aria-live', level);
    region.setAttribute('aria-atomic', 'true');
    region.style.cssText = HIDDEN;
  }
  const toggle = document.createElement('button');
  toggle.id = 'starling-a11y-toggle';
  toggle.style.cssText = HIDDEN;
  document.body.prepend(toggle);
  document.body.append(layer, polite, assertive);

  let on = false;
  let elements = [];
  let focusedId = null;
  let count = 0;

  const label = () => { toggle.textContent = on ? 'Turn off screen reader support' : 'Turn on screen reader support'; };
  const setOn = (value, remember) => {
    on = !!value;
    label();
    if (remember) { try { localStorage.setItem(KEY, on ? '1' : '0'); } catch {} }
    // The canvas is an editor that takes every key: a reader passes keys through (focus mode) inside it.
    if (on) { canvas.setAttribute('role', 'application'); canvas.setAttribute('aria-label', document.title || 'Starling'); }
    else { canvas.removeAttribute('role'); canvas.removeAttribute('aria-label'); }
    canvas.setAttribute('aria-owns', layer.id);
    ime.setAttribute('aria-hidden', on ? 'false' : 'true');
    swift.starling_a11y_enable(on ? 1 : 0);
    if (!on) { tree([]); canvas.removeAttribute('aria-owns'); }
  };
  toggle.addEventListener('click', () => { setOn(!on, true); canvas.focus({ preventScroll: true }); });

  // One element per node, reused by position; only what changed is written.
  const tree = (nodes) => {
    const box = canvas.getBoundingClientRect();
    layer.style.left = `${box.left}px`;
    layer.style.top = `${box.top}px`;
    while (elements.length < nodes.length) {
      const el = document.createElement('div');
      const index = elements.length;
      el.id = `starling-a11y-${index}`;
      el.tabIndex = -1;
      el.style.position = 'absolute';
      el.style.overflow = 'hidden';
      el.addEventListener('click', (dom) => {
        dom.preventDefault();
        swift.starling_a11y_action(index);
        canvas.focus({ preventScroll: true });
      });
      layer.append(el);
      elements.push(el);
    }
    while (elements.length > nodes.length) elements.pop().remove();
    let focused = null;
    nodes.forEach(([flags, x, y, width, height, name, value, hint], i) => {
      const el = elements[i];
      const a = describe(flags);
      for (const attr of ATTRS) {
        if (a[attr] === undefined) { if (el.hasAttribute(attr)) el.removeAttribute(attr); }
        else if (el.getAttribute(attr) !== a[attr]) el.setAttribute(attr, a[attr]);
      }
      if (name) { if (el.getAttribute('aria-label') !== name) el.setAttribute('aria-label', name); }
      else if (el.hasAttribute('aria-label')) el.removeAttribute('aria-label');
      if (hint) { if (el.getAttribute('aria-description') !== hint) el.setAttribute('aria-description', hint); }
      else if (el.hasAttribute('aria-description')) el.removeAttribute('aria-description');
      const text = value || name;
      if (el.textContent !== text) el.textContent = text;
      el.style.left = `${x}px`; el.style.top = `${y}px`;
      el.style.width = `${width}px`; el.style.height = `${height}px`;
      if (flags & FOCUSED) focused = el.id;
    });
    count = nodes.length;
    if (focused !== focusedId) {
      focusedId = focused;
      for (const target of [canvas, ime]) {
        if (focused) target.setAttribute('aria-activedescendant', focused);
        else target.removeAttribute('aria-activedescendant');
      }
    }
  };

  // The same text twice in a row would not be spoken again: clear, then write on the next task.
  const announce = (text, priority) => {
    const region = priority === 1 ? assertive : polite;
    region.textContent = '';
    setTimeout(() => { region.textContent = text; }, 30);
  };

  let wanted = false;
  try { wanted = new URLSearchParams(location.search).get('a11y') === '1' || localStorage.getItem(KEY) === '1'; } catch {}
  label();
  if (wanted) setOn(true, false);

  return {
    tree: (payload) => {
      let nodes;
      try { nodes = JSON.parse(payload); } catch (error) { console.warn('starling: a11y tree', error); return; }
      if (Array.isArray(nodes)) tree(nodes);
    },
    announce,
    setOn: (value) => setOn(value, true),
    isOn: () => on,
    // For scripts and tests: what a reader would find, one line per node.
    dump: () => elements.slice(0, count).map((el) => [el.getAttribute('role') || 'text', el.getAttribute('aria-label') || '',
      el.textContent, ...ATTRS.slice(1).filter((attr) => el.hasAttribute(attr)).map((attr) => `${attr}=${el.getAttribute(attr)}`)].join('\t')).join('\n'),
  };
}
