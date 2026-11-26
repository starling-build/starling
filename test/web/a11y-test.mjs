// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The roles the browser's screen-reader layer (web/host/a11y.js) gives each semantics node. The bits are
// WebAccessibility.Flag's (sdk/Sources/FlutterWeb/WebAccessibility.swift).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { describe } from '../../web/host/a11y.js';

const BUTTON = 1, TEXT_FIELD = 2, HEADER = 4, HAS_CHECKED = 8, CHECKED = 16, HAS_TOGGLED = 32, TOGGLED = 64;
const HAS_SELECTED = 128, SELECTED = 256, DISABLED = 512, CAN_TAP = 2048, TAB = 4096;

test('a text field is a multi-line text box', () => {
  assert.deepEqual(describe(TEXT_FIELD | CAN_TAP), { role: 'textbox', 'aria-multiline': 'true' });
});

test('a toggle is a switch, on or off', () => {
  assert.deepEqual(describe(BUTTON | HAS_TOGGLED | TOGGLED), { role: 'switch', 'aria-checked': 'true' });
  assert.deepEqual(describe(BUTTON | HAS_TOGGLED), { role: 'switch', 'aria-checked': 'false' });
});

test('a check box says checked or not', () => {
  assert.deepEqual(describe(HAS_CHECKED), { role: 'checkbox', 'aria-checked': 'false' });
  assert.deepEqual(describe(HAS_CHECKED | CHECKED | DISABLED), { role: 'checkbox', 'aria-checked': 'true', 'aria-disabled': 'true' });
});

test('a plain button has no pressed state; a selected one is pressed', () => {
  assert.deepEqual(describe(BUTTON | HAS_SELECTED | CAN_TAP), { role: 'button' });
  assert.deepEqual(describe(BUTTON | HAS_SELECTED | SELECTED), { role: 'button', 'aria-pressed': 'true' });
  assert.deepEqual(describe(CAN_TAP), { role: 'button' });
});

test('a header is a heading; plain text has no role', () => {
  assert.deepEqual(describe(HEADER), { role: 'heading', 'aria-level': '2' });
  assert.deepEqual(describe(0), {});
});

test('a ribbon tab is a tab, selected or not, never a pressed button', () => {
  assert.deepEqual(describe(TAB | HAS_SELECTED | SELECTED | CAN_TAP), { role: 'tab', 'aria-selected': 'true' });
  assert.deepEqual(describe(TAB | HAS_SELECTED | CAN_TAP), { role: 'tab', 'aria-selected': 'false' });
});
