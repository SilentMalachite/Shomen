// shomen.js: the official JavaScript of Shomen. No build step and no
// dependencies. A link with data-shomen-get or a post form with
// data-shomen-post names the id of an element, and the response replaces
// that element. Without this file the same link and form load a page.
(() => {
  "use strict";

  const TARGET_HEADER = "Shomen-Target";

  // Targets left busy for a navigation. A page restored from the
  // back-forward cache is not navigating any more.
  const handedOff = new Set();

  const sameOrigin = (url) => url.origin === location.origin;

  // Only an HTML response is parsed. Other types, such as JSON, may carry
  // markup from user input.
  const isHTML = (response) => {
    const type = response.headers.get("Content-Type") || "";
    return type.split(";")[0].trim().toLowerCase() === "text/html";
  };

  // An element of the same id in the response replaces the target. A
  // redirect loads its page. Otherwise a GET loads the URL, and a POST,
  // which must not be sent twice, shows the response as the page.
  const load = async (target, url, init) => {
    const active = document.activeElement;
    const focused = active && target.contains(active) ? active.id : "";
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
        target.replaceWith(next);
        if (focused) document.getElementById(focused)?.focus();
      } else if (init.method === "GET") {
        navigating = true;
        location.assign(url);
      } else {
        const page = new DOMParser().parseFromString(html, "text/html");
        document.documentElement.replaceWith(page.documentElement);
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
    if (!target || !/^[\x21-\x7e]+$/.test(target.id)) return null;
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
})();
