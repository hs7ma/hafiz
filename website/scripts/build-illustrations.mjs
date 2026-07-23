import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(__dirname, "..");
const rawDir = path.join(root, "illustrations", "_raw");
const outDir = path.join(root, "illustrations");

fs.mkdirSync(outDir, { recursive: true });

function wrapMotion(svg) {
  let out = svg.replace(/\n?\s*<rect[^>]*class="cls-0"[^>]*\/>/g, "");
  const i = out.indexOf(">");
  const head = out.slice(0, i + 1);
  const body = out.slice(i + 1).replace(/<\/svg>\s*$/, "");
  return `${head}
  <style>
    @media (prefers-reduced-motion: reduce) {
      .hafiz-motion { animation: none !important; }
    }
  </style>
  <g class="hafiz-motion">
    <animateTransform attributeName="transform" type="translate" values="0 1.4; 0 -1.4; 0 1.4" dur="5s" repeatCount="indefinite"/>
    ${body}
  </g>
</svg>
`;
}

function pulseWaves(svg) {
  return svg
    .replace(
      /<path class="cls-8" ([^/]*)\/>/,
      '<path class="cls-8" $1><animate attributeName="opacity" values="0.3;1;0.3" dur="2.2s" begin="0s" repeatCount="indefinite"/></path>',
    )
    .replace(
      /<path class="cls-9" ([^/]*)\/>/,
      '<path class="cls-9" $1><animate attributeName="opacity" values="0.25;1;0.25" dur="2.2s" begin="0.35s" repeatCount="indefinite"/></path>',
    )
    .replace(
      /<path class="cls-10" ([^/]*)\/>/,
      '<path class="cls-10" $1><animate attributeName="opacity" values="0.2;1;0.2" dur="2.2s" begin="0.7s" repeatCount="indefinite"/></path>',
    );
}

function growBars(svg) {
  return svg.replace(
    /<rect class="cls-8" x="([^"]+)" y="([^"]+)" width="([^"]+)" height="([^"]+)"\/>/g,
    (_m, x, y, w, h) => {
      const yy = parseFloat(y);
      const hh = parseFloat(h);
      const bottom = yy + hh;
      return `<g transform="translate(0 ${bottom})">
  <g>
    <animateTransform attributeName="transform" type="scale" values="1 0.2; 1 1; 1 0.2" dur="3.8s" repeatCount="indefinite"/>
    <rect class="cls-8" x="${x}" y="${-hh}" width="${w}" height="${h}"/>
  </g>
</g>`;
    },
  );
}

function pulseGoldPath(svg) {
  return svg.replace(
    /(<path class="cls-1" )/g,
    '$1opacity="0.85" ',
  ).replace(
    /<path class="cls-1" opacity="0.85" ([^/]*)\/>/g,
    '<path class="cls-1" opacity="0.85" $1><animate attributeName="opacity" values="0.55;1;0.55" dur="3.2s" repeatCount="indefinite"/></path>',
  );
}

const jobs = [
  { raw: "link.svg", out: "link.svg", transform: (s) => wrapMotion(pulseGoldPath(s)) },
  { raw: "mushaf.svg", out: "mushaf.svg", transform: (s) => wrapMotion(pulseWaves(s)) },
  { raw: "attendance.svg", out: "attendance.svg", transform: (s) => wrapMotion(growBars(s)) },
];

for (const job of jobs) {
  const src = path.join(rawDir, job.raw);
  const svg = fs.readFileSync(src, "utf8");
  fs.writeFileSync(path.join(outDir, job.out), job.transform(svg), "utf8");
  console.log("wrote", job.out);
}
