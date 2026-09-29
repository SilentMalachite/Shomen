// shomen.js: the official JavaScript of Shomen. No build step and no
// dependencies. A link with data-shomen-get or a post form with
// data-shomen-post names the id of an element, and the response replaces
// that element. Without this file the same link and form load a page.
// An element with data-shomen-sse holds an event stream whose fragments
// replace elements inside it, and an element with data-shomen-island runs
// the island module of that name.
(() => {
  "use strict";

  const TARGET_HEADER = "Shomen-Target";
  const ISLAND_PATH = "/islands/";
  const ISLAND_NAME = /^[a-z][a-z0-9-]*$/;

  // Targets left busy for a navigation. A page restored from the
  // back-forward cache is not navigating any more.
  const handedOff = new Set();

  // The event source of each data-shomen-sse element in the page.
  const sources = new Map();

  // Islands whose module has run.
  const mounted = new WeakSet();

  const sameOrigin = (url) => url.origin === location.origin;

  // root when it matches selector, then the elements inside it that do.
  const within = (root, selector) => [
    ...(root.matches(selector) ? [root] : []),
    ...root.querySelectorAll(selector),
  ];

  // Only an HTML response is parsed. Other types, such as JSON, may carry
  // markup from user input.
  const isHTML = (response) => {
    const type = response.headers.get("Content-Type") || "";
    return type.split(";")[0].trim().toLowerCase() === "text/html";
  };

  // Each message is a fragment. It replaces the element with the same id
  // inside the holder; a fragment for any other element is dropped. A
  // redirect can take the stream to another origin, so a message from one
  // closes it unread.
  const listen = (root) => {
    within(root, "[data-shomen-sse]").forEach((holder) => {
      if (sources.has(holder)) return;
      const url = new URL(holder.getAttribute("data-shomen-sse"), document.baseURI);
      if (!sameOrigin(url)) return;
      const source = new EventSource(url);
      sources.set(holder, source);
      source.addEventListener("message", (event) => {
        if (event.origin !== location.origin) {
          source.close();
          return;
        }
        const template = document.createElement("template");
        template.innerHTML = event.data;
        const next = template.content.firstElementChild;
        const current = next && next.id ? document.getElementById(next.id) : null;
        if (current && current !== holder && holder.contains(current)) replace(current, next);
      });
    });
  };

  // Runs the module of each island once, with the island. The name must be
  // a plain name, so it cannot lead the path anywhere else.
  const mount = (root) => {
    within(root, "[data-shomen-island]").forEach((island) => {
      const name = island.getAttribute("data-shomen-island");
      if (mounted.has(island) || !ISLAND_NAME.test(name)) return;
      mounted.add(island);
      import(ISLAND_PATH + name + ".js").then((module) => module.default(island));
    });
  };

  // Closes the stream of each holder no longer in the page, then starts
  // the streams and islands that root brings.
  const settle = (root) => {
    sources.forEach((source, holder) => {
      if (holder.isConnected) return;
      source.close();
      sources.delete(holder);
    });
    listen(root);
    mount(root);
  };

  // Puts next in place of current. When the focus was inside current, it
  // goes to the element with the same id.
  const replace = (current, next) => {
    const active = document.activeElement;
    const focused = active && current.contains(active) ? active.id : "";
    current.replaceWith(next);
    if (focused) document.getElementById(focused)?.focus();
    settle(next);
  };

  // An element of the same id in the response replaces the target. A
  // redirect loads its page. Otherwise a GET loads the URL, and a POST,
  // which must not be sent twice, shows the response as the page.
  const load = async (target, url, init) => {
    target.setAttribute("aria-busy", "true");
    // The old page stays live until a navigation commits, so it keeps the
    // target busy and a second submit still sends nothing.
    let navigating = false;
    try {
      let html;
      // A failed fetch, a failed body read, and a response that is not
      // HTML end the same way: a GET loads the URL, a POST leaves the page.
      try {
        const response = await fetch(url, { ...init, headers: { [TARGET_HEADER]: target.id } });
        if (response.redirected) {
          navigating = true;
          location.assign(response.url);
          return;
        }
        if (!isHTML(response)) throw new TypeError(`${url} did not answer HTML`);
        html = await response.text();
      } catch (error) {
        if (init.method === "GET") {
          navigating = true;
          location.assign(url);
        }
        throw error;
      }
      const template = document.createElement("template");
      template.innerHTML = html;
      const next = template.content.getElementById(target.id);
      if (next) {
        replace(target, next);
      } else if (init.method === "GET") {
        navigating = true;
        location.assign(url);
      } else {
        const page = new DOMParser().parseFromString(html, "text/html");
        document.documentElement.replaceWith(page.documentElement);
        settle(document.documentElement);
      }
    } finally {
      if (navigating) handedOff.add(target);
      else target.removeAttribute("aria-busy");
    }
  };

  addEventListener("pageshow", (event) => {
    if (!event.persisted) return;
    handedOff.forEach((target) => target.removeAttribute("aria-busy"));
    handedOff.clear();
  });

  // Returns the element to replace, or null to leave the event alone. The
  // id goes in a header, so an id that is not printable ASCII is left alone.
  const targetOf = (event, element, name) => {
    const target = document.getElementById(element.getAttribute(name));
    if (!target || !/^[\x21-\x2b\x2d-\x7e]+$/.test(target.id)) return null;
    event.preventDefault();
    return target.getAttribute("aria-busy") === "true" ? null : target;
  };

  document.addEventListener("click", (event) => {
    if (event.defaultPrevented || event.button !== 0) return;
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    if (!(event.target instanceof Element)) return;
    const link = event.target.closest("a[href][data-shomen-get]");
    if (!link || link.hasAttribute("download")) return;
    const frame = link.getAttribute("target");
    if (frame && frame !== "_self") return;
    const url = new URL(link.href);
    if (!sameOrigin(url)) return;
    const target = targetOf(event, link, "data-shomen-get");
    if (target) load(target, url, { method: "GET" });
  });

  document.addEventListener("submit", (event) => {
    const form = event.target;
    if (event.defaultPrevented || !(form instanceof HTMLFormElement)) return;
    if (!form.hasAttribute("data-shomen-post")) return;
    if ((form.getAttribute("method") || "get").toLowerCase() !== "post") return;
    const enctype = (form.getAttribute("enctype") || "application/x-www-form-urlencoded").toLowerCase();
    if (enctype !== "application/x-www-form-urlencoded") return;
    const frame = form.getAttribute("target");
    if (frame && frame !== "_self") return;
    const submitter = event.submitter;
    const overrides = ["formaction", "formmethod", "formenctype", "formtarget"];
    if (submitter && overrides.some((name) => submitter.hasAttribute(name))) return;
    const url = new URL(form.getAttribute("action") || "", document.baseURI);
    if (!sameOrigin(url)) return;
    const target = targetOf(event, form, "data-shomen-post");
    if (!target) return;
    const body = new URLSearchParams(new FormData(form, submitter));
    load(target, url, { method: "POST", body });
  });

  settle(document.documentElement);
})();
