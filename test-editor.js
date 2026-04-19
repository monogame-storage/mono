const puppeteer = require('puppeteer');
const sleep = ms => new Promise(r => setTimeout(r, ms));

(async () => {
  const browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox'] });
  const page = await browser.newPage();

  const logs = [];
  page.on('console', msg => logs.push('[' + msg.type() + '] ' + msg.text()));
  page.on('pageerror', err => logs.push('[PAGE_ERROR] ' + err.message));
  page.on('requestfailed', req => {
    logs.push('[REQ_FAIL] ' + req.method() + ' ' + req.url());
  });
  page.on('response', res => {
    const url = res.url();
    if (url.includes('api.monogame.cc') || url.includes('.png')) {
      logs.push('[NET] ' + res.status() + ' ' + (res.headers()['content-type'] || '') + ' ' + url.slice(0, 120));
    }
  });

  console.log("Loading page...");
  await page.goto('http://localhost:8090/dev/', { waitUntil: 'networkidle2', timeout: 15000 });
  await sleep(2000);

  const view = await page.evaluate(() => {
    const v = document.querySelector('.view.active');
    return v ? v.id : 'none';
  });
  console.log("Active view:", view);

  // Test isImage logic
  const imageTest = await page.evaluate(() => {
    const isImage = (n) => /\.(png|jpg|jpeg|gif|bmp|webp)$/i.test(n);
    return {
      "main.lua": isImage("main.lua"),
      "images/bg1.png": isImage("images/bg1.png"),
      "lib/terrain.lua": isImage("lib/terrain.lua"),
    };
  });
  console.log("isImage test:", JSON.stringify(imageTest));

  console.log("\nLogs:");
  logs.forEach(l => console.log("  " + l));

  await browser.close();
})();
