/* SPDX-FileCopyrightText: 2026 GPForum Contributors
 * SPDX-License-Identifier: BSD-3-Clause */
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const test = require("node:test");
const vm = require("node:vm");
const katex = require("../../assets/js/katex.min.js");
const source = fs.readFileSync(`${__dirname}/../../assets/js/mathematics.js`, "utf8");

test("the pinned local renderer produces accessible MathML for fractions, matrices and aligned equations", () => {
  for (const tex of [String.raw`\frac{-b\pm\sqrt{b^2-4ac}}{2a}`, String.raw`\begin{pmatrix}1&2\\3&4\end{pmatrix}`, String.raw`\begin{aligned}a&=b+c\\d&=e\end{aligned}`]) {
    const html = katex.renderToString(tex, { output: "mathml", trust: false, strict: "error" });
    assert.match(html, /<math/);
    assert.match(html, /<annotation encoding="application\/x-tex">/);
    assert.doesNotMatch(html, /<script|<img|<iframe|(?:href|src)="https?:\/\//);
  }
});

test("untrusted LaTeX cannot load resources, create links or loop through unbounded macros", () => {
  for (const tex of [String.raw`\includegraphics{https://evil.test/x}`, String.raw`\href{javascript:alert(1)}{x}`, String.raw`\htmlClass{evil}{x}`]) {
    const html = katex.renderToString(tex, { output: "mathml", trust: false, throwOnError: false, maxExpand: 1000 });
    assert.doesNotMatch(html, /<img|<a\s|class="evil"|src="https:/);
  }
  assert.throws(() => katex.renderToString(String.raw`\def\a{\a}\a`, {maxExpand: 1000}));
});

test("dynamic previews use bounded local rendering and retain source on a parse failure", () => {
  const expressions = [
    { textContent: String.raw`x_i^2`, dataset: { mathDisplay: "inline" } },
    { textContent: String.raw`\invalid`, dataset: { mathDisplay: "block" }, replaceChildren(code) { this.fallback = code; } },
  ];
  const calls = [];
  let mutation;
  let documentScans = 0;
  const document = {
    body: {}, documentElement: { lang: "it" },
    querySelectorAll() { documentScans++; return expressions.filter((item) => !item.dataset.mathState); },
    createElement() { return {}; },
  };
  class MutationObserver { constructor(callback) { mutation = callback; } observe() {} }
  vm.runInNewContext(source, {document, MutationObserver, katex: {
    render(tex, element, options) { calls.push({tex,options}); if (tex === String.raw`\invalid`) throw new Error("parse error"); },
  }});
  assert.equal(calls.length, 2);
  assert.equal(calls[0].options.trust, false);
  assert.equal(calls[0].options.output, "mathml");
  assert.equal(calls[0].options.maxExpand, 1000);
  assert.equal(expressions[1].fallback.textContent, String.raw`\invalid`);
  assert.match(expressions[1].title, /Formula non valida/);
  mutation([]);
  assert.equal(calls.length, 2);
  const inserted = {
    nodeType: 1, textContent: "y^2", dataset: {mathDisplay: "block"},
    matches() { return !this.dataset.mathState; },
    querySelectorAll() { return []; },
  };
  expressions.push(inserted);
  mutation([{addedNodes: [inserted]}]);
  assert.equal(calls.length, 3);
  assert.equal(calls[2].options.displayMode, true);
  mutation([{addedNodes: [inserted, {nodeType: 3}]}]);
  assert.equal(calls.length, 3);
  assert.equal(documentScans, 1, "fragment changes do not rescan the whole page");
});
