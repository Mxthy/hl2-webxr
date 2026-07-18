const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({
    args: [
      '--enable-features=SharedArrayBuffer,CrossOriginIsolation',
      '--cross-origin-isolated',
      '--no-sandbox',
      '--disable-gpu',
      '--disable-dev-shm-usage',
      '--use-gl=swiftshader',  // Software WebGL
    ]
  });
  const context = await browser.newContext({ viewport: { width: 1280, height: 1024 } });
  const page = await context.newPage();
  const allLogs = [];
  page.on('console', msg => allLogs.push(`[${msg.type()}] ${msg.text()}`));
  page.on('pageerror', err => allLogs.push(`[ERROR] ${err.message}`));

  console.log('Navigating...');
  await page.goto('http://localhost:8080/index.html', { waitUntil: 'domcontentloaded', timeout: 30000 });
  
  console.log('Waiting 50s for engine...');
  await page.waitForTimeout(50000);

  // Take a screenshot
  await page.screenshot({ path: '/app/hl2-test/engine_screenshot.png' });
  console.log('Screenshot saved to engine_screenshot.png');

  // Check canvas state
  const canvasInfo = await page.evaluate(() => {
    var canvas = document.getElementById('canvas');
    if (!canvas) return { found: false };
    return {
      found: true,
      width: canvas.width,
      height: canvas.height,
      clientWidth: canvas.clientWidth,
      clientHeight: canvas.clientHeight,
      hasContext: canvas.getContext ? true : false,
    };
  });
  console.log('Canvas info:', JSON.stringify(canvasInfo, null, 2));

  // Print key logs
  console.log('\n=== Key logs ===');
  allLogs.filter(l => 
    !l.includes('Cannot read') && !l.includes('still waiting') && 
    !l.includes('(end of list)') && !l.includes('dependency:') &&
    !l.includes('undefined symbol (report, stubbed)')
  ).slice(-40).forEach(l => console.log(l));

  await browser.close();
})();
