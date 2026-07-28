/**
 * Install LOGO.svg (brand mark on site + app) and ICON.svg (launcher/favicons/OG only).
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Resvg } from '@resvg/resvg-js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const logoSrc = path.join(root, 'LOGO1.svg');
const iconSrc = path.join(root, 'ICON.svg');

function write(rel, content) {
  const p = path.join(root, rel);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, content);
  const meta = typeof content === 'string' ? `${content.length} chars` : `${content.length} bytes`;
  console.log('wrote', rel, `(${meta})`);
}

function cleanSvg(raw) {
  let svg = raw.replace(/\r\n/g, '\n').replace(/<!--[\s\S]*?-->\n?/g, '');
  if (!/xmlns=/.test(svg)) {
    svg = svg.replace('<svg', '<svg xmlns="http://www.w3.org/2000/svg"');
  }
  return svg.trim() + '\n';
}

function darkenLogo(svg) {
  return svg
    .replaceAll('fill="#062118"', 'fill="#E8DFD0"')
    .replaceAll('fill="#C39337"', 'fill="#d4b978"')
    .replaceAll('fill="#C3983F"', 'fill="#d4b978"')
    .replaceAll('fill="#005434"', 'fill="#4a7a62"');
}

function squareWrap(innerSvg, { size, background = null, pad = 0.1, nudgeY = 0 } = {}) {
  const vb = innerSvg.match(/viewBox="([^"]+)"/)?.[1] ?? '0 0 1024 1024';
  const parts = vb.split(/\s+/).map(Number);
  const [minX, minY, vw, vh] = parts.length === 4 ? parts : [0, 0, parts[0], parts[1]];
  const inner = innerSvg
    .replace(/<\?xml[^>]*>/, '')
    .replace(/<svg[^>]*>/, '')
    .replace(/<\/svg>\s*$/, '');

  const content = size * (1 - pad * 2);
  const scale = content / Math.max(vw, vh);
  const w = vw * scale;
  const h = vh * scale;
  const x = (size - w) / 2 - minX * scale;
  // nudgeY > 0 shifts mark down (optical balance for top-heavy mihrab)
  const y = (size - h) / 2 - minY * scale + size * nudgeY;
  const bg =
    background && background !== 'none'
      ? `<rect width="${size}" height="${size}" fill="${background}"/>`
      : '';

  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">
  ${bg}
  <g transform="translate(${x.toFixed(2)} ${y.toFixed(2)}) scale(${scale.toFixed(6)})">
    ${inner}
  </g>
</svg>
`;
}

function renderPng(svg, outRel, size) {
  const png = new Resvg(svg, {
    fitTo: { mode: 'width', value: size },
  })
    .render()
    .asPng();
  write(outRel, png);
}

const logo = cleanSvg(fs.readFileSync(logoSrc, 'utf8'));
const icon = cleanSvg(fs.readFileSync(iconSrc, 'utf8'));
const logoDark = darkenLogo(logo);

// Brand logo
write('website/logo.svg', logo);
write('website/logo-on-dark.svg', logoDark);
write('assets/svg/logo.svg', logo);
write('assets/brand/logo.svg', logo);

// ICON asset kept for reference; page brand uses logo.svg
write('website/icon.svg', icon);
write('website/logo-mark.svg', logo);
// Safe margin so tab/maskable crops don't clip the outer arch
write('website/favicon.svg', squareWrap(icon, { size: 128, background: '#FBF9F2', pad: 0.16, nudgeY: 0.02 }));

// Transparent brand PNG from LOGO; launcher PNGs from ICON (generous safe zone)
renderPng(squareWrap(logo, { size: 1024, background: null, pad: 0.04 }), 'assets/brand/hafiz_logo_source.png', 1024);
renderPng(squareWrap(logo, { size: 1024, background: null, pad: 0.04 }), 'assets/brand/logo_transparent.png', 1024);
renderPng(squareWrap(logo, { size: 1024, background: '#FBF9F2', pad: 0.06 }), 'assets/brand/logo_source.png', 1024);
// ~20% pad keeps mark inside Android adaptive / launcher masks; nudgeY balances top-heavy arch
renderPng(squareWrap(icon, { size: 1024, background: '#FBF9F2', pad: 0.2, nudgeY: 0.02 }), 'assets/brand/ic_launcher.png', 1024);
renderPng(squareWrap(icon, { size: 1024, background: null, pad: 0.22, nudgeY: 0.02 }), 'assets/brand/ic_launcher_foreground.png', 1024);
renderPng(squareWrap(icon, { size: 1024, background: '#FBF9F2', pad: 0.2, nudgeY: 0.02 }), 'platform_app/assets/brand/ic_launcher.png', 1024);
renderPng(
  squareWrap(icon, { size: 1024, background: null, pad: 0.22, nudgeY: 0.02 }),
  'platform_app/assets/brand/ic_launcher_foreground.png',
  1024,
);

for (const [rel, size, pad] of [
  ['web/favicon.png', 192, 0.16],
  ['web/icons/Icon-192.png', 192, 0.16],
  ['web/icons/Icon-512.png', 512, 0.16],
  ['web/icons/Icon-maskable-192.png', 192, 0.22],
  ['web/icons/Icon-maskable-512.png', 512, 0.22],
  ['platform_app/web/favicon.png', 192, 0.16],
  ['platform_app/web/icons/Icon-192.png', 192, 0.16],
  ['platform_app/web/icons/Icon-512.png', 512, 0.16],
  ['platform_app/web/icons/Icon-maskable-192.png', 192, 0.22],
  ['platform_app/web/icons/Icon-maskable-512.png', 512, 0.22],
  ['website/apple-touch-icon.png', 180, 0.16],
  ['website/favicon-32.png', 32, 0.14],
]) {
  renderPng(squareWrap(icon, { size, background: '#FBF9F2', pad, nudgeY: 0.02 }), rel, size);
}

// OG: ivory canvas, ICON centered (621×726)
const ogScale = 520 / 726;
const ogW = 621 * ogScale;
const ogX = (1200 - ogW) / 2;
const ogY = (630 - 520) / 2;
const og = `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630">
  <rect width="1200" height="630" fill="#FBF9F2"/>
  <g transform="translate(${ogX.toFixed(2)} ${ogY.toFixed(2)}) scale(${ogScale.toFixed(6)})">
    ${icon.replace(/<\?xml[^>]*>/, '').replace(/<svg[^>]*>/, '').replace(/<\/svg>\s*$/, '')}
  </g>
</svg>
`;
renderPng(og, 'website/og-image.png', 1200);

console.log('done');
