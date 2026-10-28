import assert from 'node:assert/strict';
import { readFile, mkdir } from 'node:fs/promises';
import { createServer } from 'node:http';
import { test } from 'node:test';

const source = await readFile(new URL('../web/privacy.html', import.meta.url), 'utf8');
const published = await readFile(new URL('../invite-hosting/public/privacy.html', import.meta.url), 'utf8');
const css = await readFile(new URL('../invite-hosting/public/privacy.css', import.meta.url), 'utf8');
const policy = await readFile(new URL('../docs/privacy_policy.md', import.meta.url), 'utf8');

test('hosting policy is generated from the app policy without inline styles or scripts', () => {
  const styles = source.match(/<style>([\s\S]*?)<\/style>/);
  assert.ok(styles);
  assert.equal(css, styles[1]);
  assert.equal(published, source.replace(styles[0], '<link rel="stylesheet" href="/privacy.css">'));
  assert.doesNotMatch(published, /<script\b|<style\b|\sstyle=/i);
});

test('policy uses only the designated work email and retains core disclosures', () => {
  for (const document of [source, published, policy]) {
    const emails = document.match(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi);
    assert.deepEqual([...new Set(emails)], ['linebreakers@outlook.com']);
    for (const heading of ['AI Features', 'Service Providers', 'Retention And Deletion', 'Your Privacy Choices And Rights', 'Contact Us']) {
      assert.ok(document.includes(heading), heading);
    }
    assert.ok(document.includes('Last updated:'));
  }
});

test('policy remains readable on desktop, mobile and with enlarged text', {
  skip: !process.env.PLAYWRIGHT_MODULE,
}, async () => {
  const { chromium } = await import(process.env.PLAYWRIGHT_MODULE);
  const server = createServer((request, response) => {
    const stylesheet = request.url === '/privacy.css';
    if (!stylesheet && request.url !== '/privacy.html') {
      response.writeHead(404).end();
      return;
    }
    response.writeHead(200, {
      'Content-Type': stylesheet ? 'text/css' : 'text/html',
      'Content-Security-Policy': "default-src 'none'; style-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'",
    });
    response.end(stylesheet ? css : published);
  });
  let browser;
  try {
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    browser = await chromium.launch({ headless: true, channel: 'chrome' });
    const directory = new URL('../build/privacy-policy-qa/', import.meta.url);
    await mkdir(directory, { recursive: true });
    for (const [name, width, height, enlarged] of [
      ['desktop', 1440, 1000, false],
      ['mobile', 390, 844, false],
      ['small-mobile', 320, 740, false],
      ['large-text', 390, 844, true],
    ]) {
      const page = await browser.newPage({ viewport: { width, height } });
      const errors = [];
      page.on('pageerror', error => errors.push(error.message));
      await page.goto(`http://127.0.0.1:${server.address().port}/privacy.html`);
      if (enlarged) await page.evaluate(() => document.documentElement.style.fontSize = '200%');
      assert.equal(await page.getByRole('heading', { level: 1 }).textContent(), 'Heiro Privacy Policy');
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
      assert.equal(await page.locator('body').evaluate(element => getComputedStyle(element).backgroundColor), 'rgb(255, 255, 255)');
      await page.screenshot({ path: new URL(`${name}.png`, directory).pathname });
      await page.getByRole('heading', { name: 'Contact Us', exact: true }).scrollIntoViewIfNeeded();
      await page.screenshot({ path: new URL(`${name}-contact.png`, directory).pathname });
      assert.deepEqual(errors, []);
      await page.close();
    }
  } finally {
    await browser?.close();
    await new Promise(resolve => server.close(resolve));
  }
});
