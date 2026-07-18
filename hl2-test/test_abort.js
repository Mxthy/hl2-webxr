const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch({args:['--enable-features=SharedArrayBuffer,CrossOriginIsolation','--cross-origin-isolated','--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
  const p = await b.newPage({viewport:{width:1280,height:800}});
  const logs = [];
  p.on('console', m => logs.push('['+m.type()+'] '+m.text().substring(0,300)));
  p.on('pageerror', e => logs.push('[ERR] '+e.message.substring(0,300)));
  p.on('worker', worker => {
    worker.on('console', msg => logs.push('[WORKER] ' + msg.text().substring(0,300)));
  });
  
  await p.goto('http://localhost:8087/index.html', {waitUntil:'domcontentloaded', timeout:30000});
  await p.waitForTimeout(40000);
  
  console.log('Total logs:', logs.length);
  
  console.log('\n=== ABORT-CAUGHT ===');
  logs.filter(l => l.includes('ABORT')).forEach(l => console.log(l));
  
  console.log('\n=== Shader ===');
  logs.filter(l => l.includes('shader') || l.includes('Shader') || l.includes('combo')).forEach(l => console.log(l));
  
  console.log('\n=== Engine progress after abort ===');
  logs.filter(l => l.includes('D3D') || l.includes('render') || l.includes('frame') || l.includes('map') || l.includes('SDL') || l.includes('texture') || l.includes('material')).forEach(l => console.log(l));
  
  console.log('\n=== Last 10 ===');
  logs.filter(l => !l.includes('progressElement') && !l.includes('statusElement') && !l.includes('spinnerElement') && !l.includes('registerOrRemove') && !l.includes('GOT stub') && !l.includes('IVP') && !l.includes('Invalid UTF') && !l.includes('[GL]') && !l.includes('non-existent') && !l.includes('WORKER-INIT') && !l.includes('LoadLibrary') && !l.includes("Can't find module") && !l.includes('ABORT')).slice(-10).forEach(l => console.log(l));
  
  await b.close();
})();
