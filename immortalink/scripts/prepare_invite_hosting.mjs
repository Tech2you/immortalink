import { readFile, writeFile } from 'node:fs/promises';

// Publish the same legal pages as the app without weakening the invite site's CSP.
const directory = new URL('../invite-hosting/public/', import.meta.url);
for (const name of ['privacy', 'terms']) {
  const source = await readFile(new URL(`../web/${name}.html`, import.meta.url), 'utf8');
  const styles = source.match(/<style>([\s\S]*?)<\/style>/);
  if (!styles) throw new Error(`${name} page styles not found`);
  await writeFile(new URL(`${name}.css`, directory), styles[1]);
  await writeFile(new URL(`${name}.html`, directory),
    source.replace(styles[0], `<link rel="stylesheet" href="/${name}.css">`));
}
