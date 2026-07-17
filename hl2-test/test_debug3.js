const { chromium } = require('playwright');

(async () => {
    const browser = await chromium.launch({
        headless: true,
        args: [
            '--use-gl=swiftshader',
            '--enable-features=SharedArrayBuffer',
            '--enable-features=CrossOriginIsolation',
            '--disable-web-security',
            '--disable-features=IsolateOrigins,site-per-process',
            '--enable-unsafe-swiftshader'
        ]
    });

    // Set extra HTTP headers to ensure COOP/COEP
    const context = await browser.newContext({
        viewport: { width: 1280, height: 720 },
        extraHTTPHeaders: {}
    });

    const page = await context.newPage();

    // Capture console messages
    const logs = [];
    page.on('console', msg => logs.push(`[${msg.type()}] ${msg.text()}`));
    page.on('pageerror', err => logs.push(`[PAGE_ERROR] ${err.message}`));

    console.log('Navigating to localhost debug3 page...');
    await page.goto('http://localhost:8086/index_debug3.html?fresh=pw2', { 
        waitUntil: 'domcontentloaded',
        timeout: 120000 
    });

    // Check crossOriginIsolated status
    const isolated = await page.evaluate(() => self.crossOriginIsolated);
    console.log('crossOriginIsolated:', isolated);

    if (!isolated) {
        console.log('ERROR: crossOriginIsolated is false! SAB will fail.');
        console.log('Attempting to use tunnel URL instead...');
        
        await page.goto('https://lifestyle-vitamins-likes-dec.trycloudflare.com/index_debug3.html?fresh=pw3', { 
            waitUntil: 'domcontentloaded',
            timeout: 120000 
        });
        
        const isolated2 = await page.evaluate(() => self.crossOriginIsolated);
        console.log('crossOriginIsolated (tunnel):', isolated2);
    }

    // Wait for engine init
    console.log('Waiting for engine init (up to 3min)...');
    try {
        await page.waitForFunction(
            () => {
                const el = document.querySelector('#loading-status');
                if (!el) return false;
                const text = el.textContent;
                return text.includes('Ready') || text.includes('ABORTED') || text.includes('Error');
            },
            { timeout: 180000, polling: 2000 }
        );
    } catch(e) {
        console.log('Timeout waiting for init, capturing current state...');
    }

    // Wait for checkWasmExports
    await page.waitForTimeout(3000);

    // Get loading status
    const status = await page.evaluate(() => {
        const el = document.querySelector('#loading-status');
        return el ? el.textContent : 'NOT FOUND';
    });
    console.log('\n=== Loading Status ===');
    console.log(status);

    // Get export list
    const exports = await page.evaluate(() => {
        const el = document.querySelector('#export-list');
        return el ? el.textContent : 'NOT FOUND';
    });
    console.log('\n=== Export List ===');
    console.log(exports);

    // Get console log from custom capture
    const consoleLog = await page.evaluate(() => {
        const el = document.querySelector('#console-log');
        if (!el) return 'NOT FOUND';
        return Array.from(el.children).map(c => c.textContent).join('\n');
    });
    console.log('\n=== Console Log (last 30 entries) ===');
    consoleLog.split('\n').slice(0, 30).forEach(l => console.log(l));

    // Buttons
    const buttons = await page.evaluate(() => {
        return Array.from(document.querySelectorAll('button')).map(b => ({ 
            text: b.textContent.trim().replace(/\s+/g, ' '), 
            disabled: b.disabled 
        }));
    });
    console.log('\n=== Buttons ===');
    buttons.forEach(b => console.log(`${b.text}: ${b.disabled ? 'DISABLED' : 'ENABLED'}`));

    // Click Dump Exports if enabled
    const dumpEnabled = buttons.some(b => b.text.includes('Dump') && !b.disabled);
    if (dumpEnabled) {
        console.log('\n=== Clicking Dump Exports ===');
        await page.click('#btn-dump-exports');
        await page.waitForTimeout(2000);
        
        const dumpLog = await page.evaluate(() => {
            const el = document.querySelector('#console-log');
            return el ? Array.from(el.children).map(c => c.textContent).join('\n') : 'NOT FOUND';
        });
        console.log('=== Console after Dump (last 20) ===');
        dumpLog.split('\n').slice(0, 20).forEach(l => console.log(l));
    }

    // Click Test Bridge if enabled
    const bridgeEnabled = buttons.some(b => b.text.includes('Bridge') && !b.disabled);
    if (bridgeEnabled) {
        console.log('\n=== Clicking Test C++ Bridge ===');
        await page.click('#btn-test-bridge');
        await page.waitForTimeout(3000);
        
        const bridgeLog = await page.evaluate(() => {
            const el = document.querySelector('#console-log');
            return el ? Array.from(el.children).map(c => c.textContent).join('\n') : 'NOT FOUND';
        });
        console.log('=== Console after Bridge Test (last 15) ===');
        bridgeLog.split('\n').slice(0, 15).forEach(l => console.log(l));
    }

    // Native console logs (last 10)
    console.log('\n=== Native Console (last 10) ===');
    logs.slice(-10).forEach(l => console.log(l));

    await browser.close();
    console.log('\n=== Test Complete ===');
})();
