// Lift pure functions out of BorealisAtlas.qml so they can be tested in Node.
//
// The plugin is one QML file whose logic is ordinary JavaScript. Copying that
// logic into a test would test the copy; this reads the real source every run,
// so a test can only ever pass against the code that actually ships.
//
// Only functions that are pure given a small `root` stub are extracted. Anything
// that touches Quickshell (Process, scene, timers) stays out of reach here and is
// covered by the live checks in AGENTS.md instead.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

export const QML_PATH = fileURLToPath(new URL("../BorealisAtlas.qml", import.meta.url));

// Return the full source of `function <name>(...) { ... }`. Braces inside
// strings and comments are skipped; braces inside regex literals are left to
// balance themselves, which quantifiers like \d{1,2} always do. If extraction
// ever goes wrong the result will not compile, so it fails loudly, not quietly.
export function extractFunction(src, name) {
  const start = src.search(new RegExp(`function ${name}\\s*\\(`));
  if (start < 0) throw new Error(`function ${name} not found in ${QML_PATH}`);
  let i = src.indexOf("{", start), depth = 0;
  for (; i < src.length; i++) {
    const c = src[i], n = src[i + 1];
    if (c === "/" && n === "/") { i = src.indexOf("\n", i); continue; }
    if (c === "/" && n === "*") { i = src.indexOf("*/", i) + 1; continue; }
    if (c === '"' || c === "'" || c === "`") {
      for (i++; i < src.length && src[i] !== c; i++) if (src[i] === "\\") i++;
      continue;
    }
    if (c === "{") depth++;
    else if (c === "}" && --depth === 0) return src.slice(start, i + 1);
  }
  throw new Error(`unbalanced braces extracting ${name}`);
}

// `readonly property var name: [ ... ]` → the array itself.
export function extractArray(src, name) {
  const m = src.match(new RegExp(`property var ${name}:\\s*(\\[[^\\]]*\\])`));
  if (!m) throw new Error(`array ${name} not found`);
  return structuredClone(vm.runInNewContext(m[1]));
}

// `readonly property real|int name: 123` → the number.
export function extractNumber(src, name) {
  const m = src.match(new RegExp(`property (?:real|int) ${name}:\\s*([-\\d.]+)`));
  if (!m) throw new Error(`number ${name} not found`);
  return Number(m[1]);
}

// Build a sandbox holding the named functions as both bare globals (the QML
// calls some of them bare, e.g. moonName) and as members of `root`.
export function load(names, rootStub = {}) {
  const src = readFileSync(QML_PATH, "utf8");
  const root = { ...rootStub };
  const context = vm.createContext({ root, Math, Date, JSON, String, Number,
                                     Array, Object, isFinite, parseFloat, parseInt });
  for (const name of names) {
    vm.runInContext(extractFunction(src, name), context, { filename: `${name}()` });
    const fn = context[name];
    // Values built inside the sandbox carry ITS Object and Array prototypes,
    // so strict deep-equality calls two identical results unequal. Cloning at
    // the boundary hands tests ordinary values from this realm.
    root[name] = (...args) => {
      const v = fn(...args);
      return v === undefined || v === null || typeof v !== "object" ? v : structuredClone(v);
    };
    context[name] = fn;          // the QML calls some of these bare, e.g. moonName
  }
  return { root, src };
}
