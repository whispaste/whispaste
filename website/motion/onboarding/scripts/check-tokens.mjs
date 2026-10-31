// Fails when a composition uses a colour that is not a design token.
// Token source: design-tokens/primitives.tokens.json (every $value that is a
// #RRGGBB colour). Compositions may only use exact token hex values, no rgb()
// or hsl(), no alpha hex and no named colours.
import { readFileSync, readdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "../../../..");
const tokensFile = join(root, "design-tokens/primitives.tokens.json");
const compDir = resolve(here, "../compositions");

const tokens = new Set();
const collect = (node) => {
  if (node && typeof node === "object") {
    if (typeof node.$value === "string" && /^#[0-9a-fA-F]{6}$/.test(node.$value)) {
      tokens.add(node.$value.toUpperCase());
    }
    for (const v of Object.values(node)) collect(v);
  }
};
collect(JSON.parse(readFileSync(tokensFile, "utf8")));

let problems = 0;
for (const file of readdirSync(compDir).filter((f) => f.endsWith(".html"))) {
  const text = readFileSync(join(compDir, file), "utf8");
  const lines = text.split("\n");
  lines.forEach((line, i) => {
    const where = `${file}:${i + 1}`;
    if (/\b(rgba?|hsla?)\(/i.test(line)) {
      console.error(`${where}: rgb()/hsl() colour, use a token hex value`);
      problems++;
    }
    for (const m of line.matchAll(/(?<![\w#-])#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{3})(?![\w-])/g)) {
      const hex = m[0];
      if (hex.length !== 7 || !tokens.has(hex.toUpperCase())) {
        console.error(`${where}: "${hex}" is not a token colour`);
        problems++;
      }
    }
  });
}

if (problems > 0) {
  console.error(`${problems} colour problem(s)`);
  process.exit(1);
}
console.log(`colours ok (${tokens.size} tokens in primitives)`);
