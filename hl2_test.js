const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({
    headless: true,
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--enable-features=SharedArrayBuffer',
      '--disable-web-security',
      '--allow-running-insecure-content',
      '--js-flags=--max-old-space-size=4096',
      '--enable-unsafe-webgpu',
    ]
  });

  const ctx = await browser.newContext({
    // COOP/COEP: der lokale Server setzt die Header bereits
  });
  const page = await ctx.newPage();

  const logs = [];
  page.on('console', m => {
    const text = `[${m.type().toUpperCase()}] ${m.text()}`;
    logs.push(text);
    process.stdout.write(text + '\n');
  });
  page.on('pageerror', e => {
    const text = `[PAGEERROR] ${e.message}`;
    logs.push(text);
    process.stdout.write(text + '\n');
  });

  console.log('=== Navigating to debug.html ===');
  await page.goto('http://localhost:8080/debug.html', { timeout: 10000 });

  // Warte 5 Minuten auf Engine-Start oder Fehler
  const deadline = Date.now() + 5 * 60 * 1000;
  let lastLogCount = 0;
  let libclientDone = false;
  let engineReady = false;

  while (Date.now() < deadline) {
    await page.waitForTimeout(10000);
    
    // Check logs
    const logText = logs.join('\n');
    
    if (logText.includes('libclient.so') && !logText.includes('al http') ) {
      libclientDone = true;
    }
    if (logText.includes('Engine ready') || 
        logText.includes('Host_NewGame') || 
        logText.includes('CModelLoader') ||
        logText.includes('Steam_') ||
        logText.includes('FileSystem_Init')) {
      engineReady = true;
      console.log('\n=== ENGINE STARTED! ===');
      break;
    }

    // Check for fatal errors
    if (logText.includes('ABORT') || logText.includes('RuntimeError')) {
      console.log('\n=== FATAL ERROR DETECTED ===');
      break;
    }

    // Zeige Progress
    const newLogs = logs.slice(lastLogCount);
    lastLogCount = logs.length;
    if (newLogs.length === 0) {
      process.stdout.write('.');
    }
    
    // Screenshot
    if (logs.length % 30 === 0) {
      await page.screenshot({ path: `/tmp/hl2_screenshot_${Date.now()}.png` });
    }
  }

  console.log('\n=== FINAL STATUS ===');
  console.log('Total log entries:', logs.length);
  console.log('libclient done:', libclientDone);
  console.log('Engine ready:', engineReady);
  console.log('\nLast 20 log entries:');
  logs.slice(-20).forEach(l => console.log(l));

  await page.screenshot({ path: '/tmp/hl2_final.png' });
  await browser.close();
})();
