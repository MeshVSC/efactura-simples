(function () {
  if (window.__captureInstalled) return;
  window.__captureInstalled = true;

  function send(event) {
    try {
      event.frame = location.href;
      window.webkit.messageHandlers.capture.postMessage(event);
    } catch (e) {}
  }

  function bodyToString(body) {
    if (body == null) return null;
    if (typeof body === "string") return body;
    if (body instanceof URLSearchParams) return body.toString();
    if (body instanceof FormData) {
      var parts = [];
      body.forEach(function (value, key) {
        parts.push(key + "=" + (typeof value === "string" ? value : "[file]"));
      });
      return parts.join("&");
    }
    try { return JSON.stringify(body); } catch (e) { return String(body); }
  }

  // fetch
  var originalFetch = window.fetch;
  if (originalFetch) {
    window.fetch = function (input, init) {
      var url = typeof input === "string" ? input : (input && input.url) || "";
      var method = (init && init.method) || (input && input.method) || "GET";
      var requestHeaders = {};
      if (init && init.headers) {
        try {
          new Headers(init.headers).forEach(function (v, k) { requestHeaders[k] = v; });
        } catch (e) {}
      }
      var requestBody = bodyToString(init && init.body);
      return originalFetch.apply(this, arguments).then(function (response) {
        response.clone().text().then(function (text) {
          var responseHeaders = {};
          response.headers.forEach(function (v, k) { responseHeaders[k] = v; });
          send({
            kind: "fetch",
            method: method,
            url: new URL(url, location.href).href,
            requestHeaders: requestHeaders,
            requestBody: requestBody,
            status: response.status,
            responseHeaders: responseHeaders,
            responseBody: text
          });
        });
        return response;
      });
    };
  }

  // XMLHttpRequest
  var originalOpen = XMLHttpRequest.prototype.open;
  var originalSend = XMLHttpRequest.prototype.send;
  var originalSetHeader = XMLHttpRequest.prototype.setRequestHeader;

  XMLHttpRequest.prototype.open = function (method, url) {
    this.__capture = { method: method, url: new URL(url, location.href).href, requestHeaders: {} };
    return originalOpen.apply(this, arguments);
  };

  XMLHttpRequest.prototype.setRequestHeader = function (key, value) {
    if (this.__capture) this.__capture.requestHeaders[key] = value;
    return originalSetHeader.apply(this, arguments);
  };

  XMLHttpRequest.prototype.send = function (body) {
    var xhr = this;
    if (xhr.__capture) {
      xhr.__capture.requestBody = bodyToString(body);
      xhr.addEventListener("loadend", function () {
        var responseBody = null;
        try {
          responseBody = (xhr.responseType === "" || xhr.responseType === "text")
            ? xhr.responseText
            : "[" + xhr.responseType + "]";
        } catch (e) {}
        send({
          kind: "xhr",
          method: xhr.__capture.method,
          url: xhr.__capture.url,
          requestHeaders: xhr.__capture.requestHeaders,
          requestBody: xhr.__capture.requestBody,
          status: xhr.status,
          responseHeaders: xhr.getAllResponseHeaders(),
          responseBody: responseBody
        });
      });
    }
    return originalSend.apply(this, arguments);
  };

  // Forms
  function captureForm(form, how) {
    var fields = [];
    Array.prototype.forEach.call(form.elements, function (el) {
      if (!el.name) return;
      if ((el.type === "checkbox" || el.type === "radio") && !el.checked) return;
      fields.push({
        name: el.name,
        type: el.type || el.tagName.toLowerCase(),
        value: el.type === "password" ? "***" : el.value
      });
    });
    send({
      kind: "form-submit",
      how: how,
      method: (form.method || "GET").toUpperCase(),
      action: form.action || location.href,
      fields: fields
    });
  }

  document.addEventListener("submit", function (e) {
    captureForm(e.target, "submit-event");
  }, true);

  var originalSubmit = HTMLFormElement.prototype.submit;
  HTMLFormElement.prototype.submit = function () {
    captureForm(this, "form.submit()");
    return originalSubmit.apply(this, arguments);
  };
})();
