/**
 * يحوّل api.js من better-sqlite3 المتزامن إلى await مع طبقة db الحالية.
 */
const fs = require('fs');
const path = require('path');

const file = path.join(__dirname, '..', 'src', 'routes', 'api.js');
let src = fs.readFileSync(file, 'utf8');

// اجعل كل معالجات الراوتر async
src = src.replace(
  /router\.(get|post|put|patch|delete)\(([^,]+),\s*\(req,\s*res\)\s*=>/g,
  'router.$1($2, async (req, res) =>',
);

// db.transaction(() => { ... })()  → await db.transaction(async () => { ... })
src = src.replace(/db\.transaction\(\(\)\s*=>/g, 'await db.transaction(async () =>');
src = src.replace(/db\.transaction\(\(op\)\s*=>/g, 'await db.transaction(async (op) =>');

// أزل )() الزائدة بعد transaction إن وُجدت بصيغة })();
// النمط الشائع: })(); بعد transaction — يصبح });
// لكن فقط عندما يكون السطر هو })(); الناتج عن transaction
// أسهل: استبدال `})();` الذي يلي transaction — خطر على غيره
// نعالج يدويًا الأنماط المعروفة:
src = src.replace(
  /await db\.transaction\(async \(\) => \{([\s\S]*?)\}\)\(\);/g,
  'await db.transaction(async () => {$1});',
);

// await قبل db.prepare(...).(get|all|run)
// كرر حتى لا يتبقى شيء (لأن التعابير متداخلة)
function addAwaitPrepare(input) {
  return input.replace(
    /(?<!await\s)(?<!async\s)db\.prepare\(([\s\S]*?)\)\s*\.\s*(get|all|run)\s*\(/g,
    'await db.prepare($1).$2(',
  );
}

let prev;
do {
  prev = src;
  src = addAwaitPrepare(src);
} while (src !== prev);

// upsertById و applyOp
src = src.replace(
  /function upsertById\(/,
  'async function upsertById(',
);
src = src.replace(
  /function applyOp\(/,
  'async function applyOp(',
);

// داخل upsertById: awaits
src = src.replace(
  /async function upsertById\(table, id, insertSql, updateSql, row\) \{\n  const exists = db\.prepare/,
  'async function upsertById(table, id, insertSql, updateSql, row) {\n  const exists = await db.prepare',
);

// استدعاءات upsertById و applyOp
src = src.replace(/(?<!await\s)upsertById\(/g, 'await upsertById(');
src = src.replace(/(?<!await\s)applyOp\(/g, 'await applyOp(');

// insertSql.run / updateSql.run — هذه كائنات Statement الممرَّرة، تحتاج await
src = src.replace(
  /(?<!await\s)(insertSql|updateSql)\.run\(/g,
  'await $1.run(',
);

fs.writeFileSync(file, src);
console.log('asyncify done', file);
