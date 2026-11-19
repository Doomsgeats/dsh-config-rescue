// verify-yaml.mjs — check that a DSH profile overlay file is actually loadable.
//
// Usage:  node verify-yaml.mjs <file> [min-entries]
// Exit:   0 OK | 1 problem | 2 usage | 3 could not run (no js-yaml found)
//
// What it catches (each of these has bricked a real DSH install):
//   * UTF-8 BOM            — some editors/Set-Content add one; the loader may reject or mis-read it
//   * U+FFFD / mojibake    — a GBK<->UTF-8 round trip turned "阿里云百炼" into "闃块噷浜戠櫨鐐"
//   * not a YAML list      — a truncated file often still parses, but as a mapping or null
//   * entry count too low  — catches "the file is valid but half of it is gone"
//
// js-yaml is resolved from DSH_JS_YAML, then from any profile that already ships it,
// so this runs with the Node that DSH itself bundles and needs no npm install.

import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const target = process.argv[2];
const minEntries = Number.parseInt(process.argv[3] || "0", 10);

if (!target) {
  console.error("usage: node verify-yaml.mjs <file> [min-entries]");
  process.exit(2);
}
if (!fs.existsSync(target)) {
  console.error("FAIL missing file: " + target);
  process.exit(1);
}

let failed = false;
const buf = fs.readFileSync(target);

if (buf.length >= 3 && buf[0] === 0xef && buf[1] === 0xbb && buf[2] === 0xbf) {
  console.error("FAIL byte-order mark found (UTF-8 BOM)");
  failed = true;
}

const text = buf.toString("utf8");
if (text.includes("\uFFFD")) {
  console.error("FAIL replacement character U+FFFD present (file is not valid UTF-8)");
  failed = true;
}

// Common mojibake fragments produced by reading UTF-8 Chinese as GBK.
const MOJIBAKE = ["闃块噷", "浜戠櫨鐐", "锟斤拷", "娴嬭瘯"];
for (const m of MOJIBAKE) {
  if (text.includes(m)) {
    console.error("FAIL mojibake sequence found: " + m);
    failed = true;
  }
}

function candidateYamlModules() {
  const out = [];
  if (process.env.DSH_JS_YAML) out.push(process.env.DSH_JS_YAML);

  const harness =
    process.env.DSH_HOME ||
    (process.env.APPDATA ? path.join(process.env.APPDATA, "dsh-desktop", "harness") : "");
  const profileRoots = [];
  if (harness) profileRoots.push(path.join(harness, "profiles"));

  for (const root of profileRoots) {
    let names = [];
    try {
      names = fs.readdirSync(root);
    } catch {
      continue;
    }
    for (const name of names) {
      out.push(path.join(root, name, "node_modules", "js-yaml", "dist", "js-yaml.mjs"));
      out.push(path.join(root, name, "node_modules", "js-yaml", "dist", "js-yaml.js"));
    }
  }
  return out;
}

let yaml = null;
for (const candidate of candidateYamlModules()) {
  if (!candidate || !fs.existsSync(candidate)) continue;
  try {
    yaml = await import(pathToFileURL(candidate).href);
    break;
  } catch {
    /* try the next candidate */
  }
}

if (!yaml) {
  console.error("WARN js-yaml not found; parse check skipped (set DSH_JS_YAML to its path)");
  process.exit(failed ? 1 : 3);
}

try {
  const doc = yaml.load(text);
  if (doc === null || doc === undefined) {
    console.error("FAIL parsed to null/empty (root must be a list)");
    failed = true;
  } else if (!Array.isArray(doc)) {
    console.error("FAIL root is " + typeof doc + ", expected a YAML list");
    failed = true;
  } else {
    const withId = doc.filter((e) => e && typeof e === "object" && e.id).length;
    console.log("OK list with " + doc.length + " entries (" + withId + " with id)");
    if (Number.isFinite(minEntries) && minEntries > 0 && doc.length < minEntries) {
      console.error(
        "FAIL only " + doc.length + " entries, expected at least " + minEntries + " (truncated file?)"
      );
      failed = true;
    }
  }
} catch (err) {
  const msg = String(err && err.message ? err.message : err).split("\n")[0];
  console.error("FAIL yaml parse error: " + msg);
  failed = true;
}

process.exit(failed ? 1 : 0);