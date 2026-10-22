/* SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
 * SPDX-License-Identifier: BSD-3-Clause */
(() => {
  "use strict";
  const italian = document.documentElement.lang.startsWith("it");
  const label = (en, it) => italian ? it : en;
  const initialize = () => {
    const posts = [...document.querySelectorAll("#posts .post[id]")];
    if (!posts.length) return;
    let navigation = document.getElementById("thread-page-navigation");
    if (!navigation) {
      navigation = document.createElement("nav");
      navigation.id = "thread-page-navigation";
      navigation.className = "toolbar";
      navigation.setAttribute("aria-label", label("Posts on this page", "Messaggi in questa pagina"));
      document.getElementById("posts").before(navigation);
    }
    navigation.replaceChildren();
    [[label("First post", "Primo messaggio"), posts[0]],
      [label("Last post on this page", "Ultimo messaggio della pagina"), posts.at(-1)]].forEach(([text, post]) => {
      const link = document.createElement("a");
      link.href = `#${post.id}`;
      link.textContent = text;
      navigation.append(link);
    });
    const select = document.createElement("select");
    select.setAttribute("aria-label", label("Go to post", "Vai al messaggio"));
    const placeholder = document.createElement("option");
    placeholder.textContent = label("Go to post…", "Vai al messaggio…");
    placeholder.value = "";
    select.append(placeholder);
    posts.forEach((post, index) => {
      const option = document.createElement("option");
      option.value = post.id;
      const heading = post.querySelector(".post__header");
      const ordinal = post.querySelector(".post__permalink")?.textContent.trim() || String(index + 1);
      option.textContent = `${ordinal} · ${(heading?.textContent || post.id).trim().replace(/\s+/g, " ").slice(0, 100)}`;
      select.append(option);
    });
    select.addEventListener("change", () => {
      const target = document.getElementById(select.value);
      if (!target) return;
      location.hash = target.id;
      target.setAttribute("tabindex", "-1");
      target.focus();
    });
    navigation.append(select);
  };
  initialize();
  document.addEventListener("htmx:afterSwap", initialize);
  document.addEventListener("htmx:oobAfterSwap", initialize);
})();
