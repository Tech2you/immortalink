import assert from 'node:assert/strict';
import { readFile, mkdir } from 'node:fs/promises';
import { createServer } from 'node:http';
import { test } from 'node:test';

const source = await readFile(new URL('../web/terms.html', import.meta.url), 'utf8');
const published = await readFile(new URL('../invite-hosting/public/terms.html', import.meta.url), 'utf8');
const css = await readFile(new URL('../invite-hosting/public/terms.css', import.meta.url), 'utf8');

test('service terms keep the Apple licence and mandatory rights alongside a prominent recovery notice', () => {
  const styles = source.match(/<style>([\s\S]*?)<\/style>/);
  assert.equal(css, styles[1]);
  assert.equal(published, source.replace(styles[0], '<link rel="stylesheet" href="/terms.css">'));
  assert.doesNotMatch(published, /<script\b|<style\b|\sstyle=/i);
  assert.match(published, /https:\/\/www.apple.com\/legal\/internet-services\/itunes\/dev\/stdeula\//);
  assert.match(published, /gross negligence/);
  assert.match(published, /mandatory consumer or data-protection rights/);
  assert.match(published, /Ending a subscription does not itself delete existing memories/);
  assert.match(published, /Heiro should not be your only copy/);
  assert.match(published, /href="#liability"/);
  assert.deepEqual([...new Set(published.match(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi))], ['linebreakers@outlook.com']);
});

test('service terms render without horizontal overflow and the liability link is usable', {
  skip: !process.env.PLAYWRIGHT_MODULE,
}, async () => {
  const { chromium } = await import(process.env.PLAYWRIGHT_MODULE);
  const server = createServer((req, res) => {
    if (!['/terms.html', '/terms.css'].includes(req.url)) return res.writeHead(404).end();
    res.writeHead(200, { 'Content-Type': req.url.endsWith('.css') ? 'text/css' : 'text/html',
      'Content-Security-Policy': "default-src 'none'; style-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'" });
    res.end(req.url.endsWith('.css') ? css : published);
  });
  let browser;
  try {
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    browser = await chromium.launch({ headless: true, channel: 'chrome' });
    const directory = new URL('../build/service-terms-qa/', import.meta.url);
    await mkdir(directory, { recursive: true });
    for (const [name, width, height, scale] of [['desktop', 1440, 1000, 1], ['mobile', 390, 844, 1], ['large-text', 320, 740, 2]]) {
      const page = await browser.newPage({ viewport: { width, height } });
      await page.goto(`http://127.0.0.1:${server.address().port}/terms.html`);
      if (scale > 1) await page.evaluate(() => document.documentElement.style.fontSize = '200%');
      assert.equal(await page.getByRole('heading', { level: 1 }).textContent(), 'Heiro Service Terms');
      assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
      await page.screenshot({ path: new URL(`${name}.png`, directory).pathname });
      await page.getByRole('link', { name: 'liability limitations below' }).click();
      assert(await page.getByRole('heading', { name: 'Liability and consumer rights' }).isVisible());
      await page.close();
    }
  } finally {
    await browser?.close();
    await new Promise(resolve => server.close(resolve));
  }
});
