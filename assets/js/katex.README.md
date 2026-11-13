# Bundled KaTeX

`katex.min.js` is the unmodified browser build from KaTeX **0.19.1**, under
the MIT licence in `katex.LICENSE`.

Source: https://registry.npmjs.org/katex/-/katex-0.19.1.tgz

The downloaded archive was checked against its npm package integrity:

```text
sha512-jG8uKntjSEcm2EpQOh0XturpPuuC9r3Sq5HLHdsFdWZT27E672SF19QEi+of0/YeOy15lDgRhKvr5614uRrEfA==
```

Good Phorum uses MathML output only. No KaTeX stylesheet, web fonts, auto-render
extension, CDN, HTML extension or user-defined global macro state is loaded.
The core adapter is `mathematics.js`; the fixed plugin capability returns
only validated LaTeX source spans. Update the package deliberately, review
its licence and input-handling changes, and run the equation and browser
tests before replacing this file.
