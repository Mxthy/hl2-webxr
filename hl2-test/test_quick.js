const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch({
    args: ['--enable-features=SharedArrayBuffer,CrossOriginIsolation','--cross-origin-isolated','--no-sandbox','--disable-gpu','--disable-dev-shm-usage']
  });
  const page = await (await browser.newContext({viewport:{width:1280,height:1024}})).newPage();
  var errs = [];
  page.on('pageerror', e => errs.push(e.message.substring(0,150)));
  page.on('console', m => {
    const t = m.text();
    if (t.includes('SET-MAIN') || t.includes('POST-EXIT') || t.includes('POST-UNWIND') || 
        t.includes('WORKER]') || t.includes('HANDLE-EXC') || t.includes('render') || 
        t.includes('Render') || t.includes('loop') || t.includes('Loop') || 
        t.includes('error') || t.includes('Error') || t.includes('abort'))
      console.log('['+m.type()+'] '+t.substring(0,200));
  });
  await page.goto('http://localhost:8087/index.html', {waitUntil:'domcontentloaded',timeout:30000});
  await page.waitForTimeout(15000);
  
  const st = await page.evaluate(() => ({
    loop: typeof MainLoop!=='undefined'?MainLoop.running:'undef',
    func: typeof MainLoop!=='undefined'?typeof MainLoop.func:'undef',
    iter: typeof MainLoop!=='undefined'&&MainLoop.iterFunc?MainLoop.iterFunc.name:'none',
    calledMain: Module.calledMain,
    canvas: document.getElementById('game-canvas')?document.getElementById('game-canvas').width+'x'+document.getElementById('game-canvas').height:'none',
  }));
  console.log('\n=== STATE ===');
  console.log(JSON.stringify(st,null,2));
  if (errs.length) { console.log('\nErrors:'); errs.forEach(e=>console.log('  '+e)); }
  
  await page.screenshot({path:'/app/hl2-test/quick_screenshot.png'});
  console.log('Screenshot saved');
  await browser.close();
})();
