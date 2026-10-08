#!/usr/bin/env node
// Capture slide previews from the real Starling Slides canvas. Serve the
// prepared ui/desktop first, then run this with its URL (default :8011/desktop).
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
const root = fileURLToPath(new URL('../../', import.meta.url));
const url = process.argv[2] || 'http://127.0.0.1:8011/desktop/';
for (const [name, width, height, port] of [['wide',1280,880,9501],['tall',450,894,9502]]) {
  const profile = mkdtempSync(`${tmpdir()}/landing-posters-`);
  try {
    const actions = ['wait','3000','eval','if (!window.starling || !document.getElementById("stage").classList.contains("live")) throw Error("Slides did not start")'];
    for (let i=0; i<6; i++) {
      actions.push('eval', `window.starling.swift.office_landing_go(${i})`, 'wait', '1200',
        'canvas',resolve(root,`ui/desktop/slides/${name}-${i+1}.png`));
    }
    const result = spawnSync(process.execPath,[resolve(root,'build/tools/web-drive.mjs'),...actions],{
      env:{...process.env,URL:url,W:String(width),H:String(height),PORT:String(port),CHROME_PROFILE:profile},
      stdio:'inherit',
    });
    if (result.status !== 0) throw Error(`Could not capture ${name} slides`);
  } finally { rmSync(profile,{recursive:true,force:true,maxRetries:5,retryDelay:200}); }
}
