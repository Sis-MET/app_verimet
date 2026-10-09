// Genera web/eliminar-cuenta/config.js con la URL y la clave pública de
// app/config/supabase.prod.json (la misma configuración con que se compila la
// app). La página y su config.js se publican juntos en el sitio web.
import { readFile, writeFile } from 'node:fs/promises';

const source = new URL('../app/config/supabase.prod.json', import.meta.url);
const target = new URL('../web/eliminar-cuenta/config.js', import.meta.url);
const config = JSON.parse(await readFile(source, 'utf8'));
const url = String(config.SUPABASE_URL || '');
const key = String(config.SUPABASE_PUBLISHABLE_KEY || '');
if (!/^https:\/\/[^/]+$/.test(url.replace(/\/$/, ''))) throw new Error('SUPABASE_URL no es una URL HTTPS válida.');
if (!key.startsWith('sb_publishable_') && !key.startsWith('eyJ')) throw new Error('Falta la clave pública de Supabase.');
if (key.includes('service_role') || key.startsWith('sb_secret_')) throw new Error('Nunca publiques una clave de servidor.');
await writeFile(target, `// Generado por scripts/build-account-deletion-page.mjs. No se versiona.\nwindow.IVMET_CONFIG = ${JSON.stringify({ url, publishableKey: key }, null, 2)};\n`);
console.log('web/eliminar-cuenta/config.js listo. Publica la carpeta web/eliminar-cuenta/.');
