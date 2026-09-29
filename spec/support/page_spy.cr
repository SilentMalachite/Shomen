# Runs before the scripts of each page (Browser#before_load) and records
# in window.shomenSeen every addEventListener call and every EventSource
# the page opens. Not strict, so a call on the global object records
# window as its target.
PAGE_SPY = <<-JS
  (() => {
    const seen = {listeners: [], sources: []};
    window.shomenSeen = seen;
    const add = EventTarget.prototype.addEventListener;
    EventTarget.prototype.addEventListener = function (type, listener, options) {
      seen.listeners.push({target: this, type});
      return add.call(this, type, listener, options);
    };
    const Source = window.EventSource;
    window.EventSource = class extends Source {
      constructor(url, init) {
        super(url, init);
        seen.sources.push(this);
      }
    };
  })();
  JS
