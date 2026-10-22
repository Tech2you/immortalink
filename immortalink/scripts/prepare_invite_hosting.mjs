import { readFile, writeFile } from 'node:fs/promises';

// Publish the same policy as the app without weakening the invite site's CSP.
const source = await readFile(new URL('../web/privacy.html', import.meta.url), 'utf8');
const styles = source.match(/<style>([\s\S]*?)<\/style>/);
if (!styles) throw new Error('Privacy policy styles not found');
const directory = new URL('../invite-hosting/public/', import.meta.url);
await writeFile(new URL('privacy.css', directory), styles[1]);
await writeFile(
  new URL('privacy.html', directory),
  source.replace(styles[0], '<link rel="stylesheet" href="/privacy.css">'),
);
