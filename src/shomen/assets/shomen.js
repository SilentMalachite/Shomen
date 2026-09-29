// shomen.js: the official JavaScript of Shomen. No build step and no
// dependencies. A link with data-shomen-get or a post form with
// data-shomen-post names the id of an element, and the response replaces
// that element. Without this file the same link and form load a page.
(() => {
  "use strict";

  const TARGET_HEADER = "Shomen-Target";

  const sameOrigin = (url) => url.origin === location.origin;

  // An element of the same id in the response replaces the target. A
  // redirect loads its page. Otherwise a GET loads the URL, and a POST,
  // which must not be sent twice, shows the response as the page.
  const load = async (target, url, init) => {
    const active = document.activeElement;
    const focused = active && target.contains(active) ? active.id : "";
    target.setAttribute("aria-busy", "true");
    try {
      let response;
      try {
        response = await fetch(url, { ...init, headers: { [TARGET_HEADER]: target.id } });
      } catch (error) {
        if (init.method === "GET") location.assign(url);
        throw error;
      }
      if (response.redirected) {
        location.assign(response.url);
        return;
      }
      const html = await response.text();
      const template = document.createElement("template");
      template.innerHTML = html;
      const next = template.content.getElementById(target.id);
      if (next) {
        target.replaceWith(next);
        if (focused) document.getElementById(focused)?.focus();
      } else if (init.method === "GET") {
        location.assign(url);
      } else {
        const page = new DOMParser().parseFromString(html, "text/html");
        document.documentElement.replaceWith(page.documentElement);
      }
    } finally {
      target.removeAttribute("aria-busy");
    }
  };

  // Returns the element to replace, or null to leave the event alone.
  const targetOf = (event, element, name) => {
    const target = document.getElementById(element.getAttribute(name));
    if (!target) return null;
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
