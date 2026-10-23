/* SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
 * SPDX-License-Identifier: BSD-3-Clause */
(() => {
  "use strict";
  const italian = document.documentElement.lang.startsWith("it");
  const label = (en, it) => italian ? it : en;
  let observer;
  let observedPosts = [];
  const initialize = () => {
    const posts = [...document.querySelectorAll("#posts .post[id]")];
    if (!posts.length) return;
    if (document.getElementById("thread-page-navigation") && posts.length === observedPosts.length &&
        posts.every((post, index) => post === observedPosts[index])) return;
    observer?.disconnect();
    observedPosts = posts;
    let navigation = document.getElementById("thread-page-navigation");
    if (!navigation) {
      navigation = document.createElement("nav");
      navigation.id = "thread-page-navigation";
      navigation.className = "toolbar";
      navigation.setAttribute("aria-label", label("Posts on this page", "Messaggi in questa pagina"));
      document.getElementById("posts").before(navigation);
    }
    const previousPost = navigation.dataset.currentPost;
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
      const author = heading?.querySelector?.(".post__byline > a")?.textContent.trim();
      option.textContent = author ? `${ordinal} · ${author}` : ordinal;
      select.append(option);
    });
    navigation.append(select);
    const reading = document.createElement("div");
    reading.className = "thread-reading-progress";
    const position = document.createElement("span");
    position.className = "thread-reading-progress__position";
    const progress = document.createElement("progress");
    progress.max = posts.length;
    progress.setAttribute("aria-label", label("Reading progress on this page", "Avanzamento della lettura in questa pagina"));
    const previous = document.createElement("button");
    const next = document.createElement("button");
    [previous, next].forEach(button => { button.type = "button"; button.className = "button--quiet"; });
    previous.textContent = label("Previous", "Precedente");
    next.textContent = label("Next", "Successivo");
    let current = Math.max(0, posts.findIndex(post => post.id === previousPost));
    const update = index => {
      current = index;
      navigation.dataset.currentPost = posts[index].id;
      const ordinal = posts[index].querySelector(".post__permalink")?.textContent.trim() || `#${index + 1}`;
      position.textContent = label(`${ordinal} · ${index + 1}/${posts.length} on this page`, `${ordinal} · ${index + 1}/${posts.length} in pagina`);
      progress.value = index + 1;
      select.value = posts[index].id;
      previous.disabled = index === 0;
      next.disabled = index === posts.length - 1;
    };
    const jump = index => {
      if (index < 0 || index >= posts.length) return;
      update(index);
      location.hash = posts[index].id;
      posts[index].setAttribute("tabindex", "-1");
      posts[index].focus({ preventScroll: true });
    };
    previous.addEventListener("click", () => jump(current - 1));
    next.addEventListener("click", () => jump(current + 1));
    select.addEventListener("change", () => {
      const index = posts.findIndex(post => post.id === select.value);
      if (index >= 0) jump(index);
    });
    reading.append(previous, position, progress, next);
    navigation.append(reading);
    if (document.getElementById("thread-explore")) {
      const explore = document.createElement("button");
      explore.type = "button";
      explore.className = "button--quiet";
      explore.textContent = label("Explore", "Esplora");
      explore.setAttribute("aria-label", label("Explore discussion", "Esplora discussione"));
      explore.setAttribute("popovertarget", "thread-explore");
      reading.before(explore);
    }
    update(current);
    // One observer per discussion; no scroll loop or history writes while reading.
    if (typeof IntersectionObserver !== "undefined") {
      const visible = new Set();
      observer = new IntersectionObserver(entries => {
        entries.forEach(entry => {
          if (entry.isIntersecting) visible.add(entry.target);
          else visible.delete(entry.target);
        });
        const candidate = [...visible].sort((a, b) =>
          Math.abs(a.getBoundingClientRect().top - 120) - Math.abs(b.getBoundingClientRect().top - 120))[0];
        if (candidate) update(posts.indexOf(candidate));
      }, { rootMargin: "-100px 0px -35% 0px", threshold: 0 });
      posts.forEach(post => observer.observe(post));
    }
  };
  initialize();
  document.addEventListener("htmx:afterSwap", initialize);
  document.addEventListener("htmx:oobAfterSwap", initialize);
})();
