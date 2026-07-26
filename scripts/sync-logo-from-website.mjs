/**
 * Sync website/logo.svg into Flutter assets and rasterize launcher/brand PNGs.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Resvg } from "@resvg/resvg-js";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const srcPath = path.join(root, "website", "logo.svg");

function write(rel, content) {
  const p = path.join(root, rel);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, content);
  console.log("wrote", rel);
}

function squareWrap(innerSvg, { size, background = null, pad = 0.1 } = {}) {
  const vb = innerSvg.match(/viewBox="([^"]+)"/)?.[1] ?? "0 0 820 420";
  const parts = vb.split(/\s+/).map(Number);
  const [minX, minY, vw, vh] = parts.length === 4 ? parts : [0, 0, parts[0], parts[1]];
  const inner = innerSvg
    .replace(/<\?xml[^>]*>/, "")
    .replace(/<svg[^>]*>/, "")
    .replace(/<\/svg>\s*$/, "");

  const content = size * (1 - pad * 2);
  const scale = content / Math.max(vw, vh);
  const w = vw * scale;
  const h = vh * scale;
  const x = (size - w) / 2 - minX * scale;
  const y = (size - h) / 2 - minY * scale;
  const bg =
    background && background !== "none"
      ? `<rect width="${size}" height="${size}" fill="${background}"/>`
      : "";

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
    fitTo: { mode: "width", value: size },
  })
    .render()
    .asPng();
  write(outRel, png);
}

const light = fs.readFileSync(srcPath, "utf8");
write("assets/svg/logo.svg", light);
write("assets/brand/logo.svg", light);

renderPng(squareWrap(light, { size: 1024, background: null, pad: 0.06 }), "assets/brand/hafiz_logo_source.png", 1024);
renderPng(squareWrap(light, { size: 1024, background: null, pad: 0.06 }), "assets/brand/logo_transparent.png", 1024);
renderPng(squareWrap(light, { size: 1024, background: "#FBF9F2", pad: 0.08 }), "assets/brand/logo_source.png", 1024);
renderPng(squareWrap(light, { size: 1024, background: "#FBF9F2", pad: 0.08 }), "assets/brand/ic_launcher.png", 1024);
renderPng(squareWrap(light, { size: 1024, background: null, pad: 0.12 }), "assets/brand/ic_launcher_foreground.png", 1024);

renderPng(squareWrap(light, { size: 1024, background: "#FBF9F2", pad: 0.08 }), "platform_app/assets/brand/ic_launcher.png", 1024);
renderPng(
  squareWrap(light, { size: 1024, background: null, pad: 0.12 }),
  "platform_app/assets/brand/ic_launcher_foreground.png",
  1024,
);

for (const [rel, size, pad] of [
  ["web/favicon.png", 192, 0.1],
  ["web/icons/Icon-192.png", 192, 0.1],
  ["web/icons/Icon-512.png", 512, 0.1],
  ["web/icons/Icon-maskable-192.png", 192, 0.18],
  ["web/icons/Icon-maskable-512.png", 512, 0.18],
]) {
  renderPng(squareWrap(light, { size, background: "#FBF9F2", pad }), rel, size);
}

console.log("done");
