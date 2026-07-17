const { chromium } = require('playwright');

(async () => {
    const browser = await chromium.launch({
        headless: true,
        args: [
            '--use-gl=angle',
            '--use-angle=swiftshader',
            '--enable-unsafe-swiftshader',
            '--enable-features=SharedArrayBuffer,CrossOriginIsolation',
            '--disable-features=IsolateOrigins,site-per-process',
            '--no-sandbox'
        ]
    });

    const context = await browser.newContext({
        viewport: { width: 1280, height: 720 }
    });

    const page = await context.newPage();

    const logs = [];
    page.on('console', msg => logs.push(`[${msg.type()}] ${msg.text()}`));
    page.on('pageerror', err => logs.push(`[PAGE_ERROR] ${err.message}`));

    console.log('Navigating to localhost...');
    await page.goto('http://localhost:8086/index_debug3.html?fresh=pw4', { 
        waitUntil: 'domcontentloaded',
        timeout: 120000 
    });

    // Check crossOriginIsolated
    const isolated = await page.evaluate(() => self.crossOriginIsolated);
    console.log('crossOriginIsolated:', isolated);

    if (!isolated) {
        console.log('crossOriginIsolated=false — trying to set via route interceptor...');
        
        // Try intercepting and adding COOP/COEP headers
        await context.route('**/*', route => {
            const headers = route.request().headers();
            headers['Cross-Origin-Opener-Policy'] = 'same-origin';
            headers['Cross-Origin-Embedder-Policy'] = 'require-corp';
            route.continue({ headers });
        });
        
        // Reload with new headers
        await page.reload({ waitUntil: 'domcontentloaded', timeout: 120000 });
        const isolated2 = await page.evaluate(() => self.crossOriginIsolated);
        console.log('crossOriginIsolated after route:', isolated2);
        
        if (!isolated2) {
            // Last resort: use --headless=new via CDP
            console.log('crossOriginIsolated still false. Trying tunnel URL...');
            await page.goto('https://lifestyle-vitamins-likes-dec.trycloudflare.com/index_debug3.html?fresh=pw5', { 
                waitUntil: 'domcontentloaded',
                timeout: 120000 
            });
            const isolated3 = await page.evaluate(() => self.crossOriginIsolated);
            console.log('crossOriginIsolated (tunnel):', isolated3);
        }
    }

    // Wait for engine init
    console.log('Waiting for engine init...');
    try {
        await page.waitForFunction(
            () => {
                const el = document.querySelector('#loading-status');
                if (!el) return false;
                const text = el.textContent;
                return text.includes('Ready') || text.includes('ABORTED') || text.includes('Error') || text.includes('ABORT');
            },
            { timeout: 180000, polling: 2000 }
        );
    } catch(e) {
        console.log('Timeout waiting for init...');
    }

    await page.waitForTimeout(3000);

    const status = await page.evaluate(() => {
        const el = document.querySelector('#loading-status');
        return el ? el.textContent : 'NOT FOUND';
    });
    console.log('\n=== Loading Status ===');
    console.log(status);

    const exports = await page.evaluate(() => {
        const el = document.querySelector('#export-list');
        return el ? el.textContent : 'NOT FOUND';
    });
    console.log('\n=== Export List ===');
    console.log(exports);

    const consoleLog = await page.evaluate(() => {
        const el = document.querySelector('#console-log');
        if (!el) return 'NOT FOUND';
        return Array.from(el.children).map(c => c.textContent).join('\n');
    });
    console.log('\n=== Console Log (last 30) ===');
    consoleLog.split('\n').slice(0, 30).forEach(l => console.log(l));

    const buttons = await page.evaluate(() => {
        return Array.from(document.querySelectorAll('button')).map(b => ({ 
            text: b.textContent.trim().replace(/\s+/g, ' '), 
            disabled: b.disabled 
        }));
    });
    console.log('\n=== Buttons ===');
    buttons.forEach(b => console.log(`${b.text}: ${b.disabled ? 'DISABLED' : 'ENABLED'}`));

    // Click Dump if enabled
    const dumpEnabled = buttons.some(b => b.text.includes('Dump') && !b.disabled);
    if (dumpEnabled) {
        console.log('\n=== Clicking Dump Exports ===');
        await page.click('#btn-dump-exports');
        await page.waitForTimeout(2000);
        const dumpLog = await page.evaluate(() => {
            const el = document.querySelector('#console-log');
            return el ? Array.from(el.children).map(c => c.textContent).join('\n') : '';
        });
        dumpLog.split('\n').slice(0, 20).forEach(l => console.log(l));
    }

    // Click Bridge if enabled
    const bridgeEnabled = buttons.some(b => b.text.includes('Bridge') && !b.disabled);
    if (bridgeEnabled) {
        console.log('\n=== Clicking Test C++ Bridge ===');
        await page.click('#btn-test-bridge');
        await page.waitForTimeout(3000);
        const bridgeLog = await page.evaluate(() => {
            const el = document.querySelector('#console-log');
            return el ? Array.from(el.children).map(c => c.textContent).join('\n') : '';
        });
        bridgeLog.split('\n').slice(0, 15).forEach(l => console.log(l));
    }

    console.log('\n=== Native Console (last 10) ===');
    logs.slice(-10).forEach(l => console.log(l));

    await browser.close();
    console.log('\n=== Done ===');
})();
