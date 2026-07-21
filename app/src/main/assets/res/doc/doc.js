(function () {
  "use strict";

  var keywords = new Set([
    "and", "break", "do", "else", "elseif", "end", "false", "for",
    "function", "goto", "if", "in", "local", "nil", "not", "or",
    "repeat", "return", "then", "true", "until", "while",
    "abstract", "case", "catch", "continue", "default", "defer", "finally",
    "import", "interface", "lambda", "module", "switch", "try", "when"
  ]);

  var builtins = new Set([
    "activity", "android", "assert", "collectgarbage", "error", "getmetatable",
    "ipairs", "load", "loadfile", "loadstring", "luajava",
    "next", "pairs", "pcall", "print", "rawequal", "rawget", "rawlen", "rawset",
    "require", "select", "setmetatable", "superCall", "this", "tonumber", "tostring", "type",
    "xpcall", "Object", "Runnable", "ArrayList", "HashMap", "Map", "Closeable"
  ]);

  var operators = /^(?:\.\.|\.\.=?|->|=>|==|~=|!=|<=|>=|<<=?|>>=?|&&|\|\||\+=|-=|\*=|\/=|%=|\^=|\/\/=|\/\/|\*\*|[+\-*\/%^#=<>~&|?:`!\\])/;

  function escapeHtml(text) {
    return text
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");
  }

  function span(kind, text) {
    return '<span class="tok-' + kind + '">' + escapeHtml(text) + '</span>';
  }

  function readLongBracket(source, index) {
    var match = /^\[(=*)\[/.exec(source.slice(index));
    if (!match) return null;
    var close = "]" + match[1] + "]";
    var start = index + match[0].length;
    var end = source.indexOf(close, start);
    return end === -1 ? source.length : end + close.length;
  }

  function highlightLua(source) {
    var out = "";
    var i = 0;

    while (i < source.length) {
      var ch = source[i];
      var next = source[i + 1];

      if (ch === "-" && next === "-") {
        var longCommentEnd = readLongBracket(source, i + 2);
        if (longCommentEnd !== null) {
          out += span("comment", source.slice(i, longCommentEnd));
          i = longCommentEnd;
          continue;
        }
        var lineEnd = source.indexOf("\n", i);
        if (lineEnd === -1) lineEnd = source.length;
        out += span("comment", source.slice(i, lineEnd));
        i = lineEnd;
        continue;
      }

      if (ch === "'" || ch === '"') {
        var quote = ch;
        var j = i + 1;
        while (j < source.length) {
          if (source[j] === "\\") {
            j += 2;
            continue;
          }
          if (source[j] === quote) {
            j++;
            break;
          }
          j++;
        }
        out += span("string", source.slice(i, j));
        i = j;
        continue;
      }

      var longStringEnd = readLongBracket(source, i);
      if (longStringEnd !== null) {
        out += span("string", source.slice(i, longStringEnd));
        i = longStringEnd;
        continue;
      }

      if (/\d/.test(ch)) {
        var number = /^(?:0[xX][\da-fA-F]+(?:\.[\da-fA-F]*)?(?:[pP][+-]?\d+)?|\d+(?:\.\d*)?(?:[eE][+-]?\d+)?)/.exec(source.slice(i));
        if (number) {
          out += span("number", number[0]);
          i += number[0].length;
          continue;
        }
      }

      if (/[A-Za-z_]/.test(ch)) {
        var word = /^[A-Za-z_]\w*/.exec(source.slice(i))[0];
        if (keywords.has(word)) out += span("keyword", word);
        else if (builtins.has(word)) out += span("builtin", word);
        else out += escapeHtml(word);
        i += word.length;
        continue;
      }

      var op = operators.exec(source.slice(i));
      if (op) {
        out += span("operator", op[0]);
        i += op[0].length;
        continue;
      }

      out += escapeHtml(ch);
      i++;
    }

    return out;
  }

  function applyHighlighting() {
    document.querySelectorAll('pre code.language-lua').forEach(function (code) {
      if (code.dataset.highlighted === "true") return;
      code.innerHTML = highlightLua(code.textContent || "");
      code.dataset.highlighted = "true";
    });
  }

  function slugify(text, used) {
    var base = text.trim().toLowerCase()
      .replace(/[\s\u3000]+/g, "-")
      .replace(/[^\w\-\u4e00-\u9fa5]+/g, "")
      .replace(/-+/g, "-")
      .replace(/^-|-$/g, "");
    if (!base) base = "section";
    var slug = base;
    var index = 2;
    while (used[slug] || document.getElementById(slug)) {
      slug = base + "-" + index;
      index++;
    }
    used[slug] = true;
    return slug;
  }

  function setupHeadings() {
    var used = {};
    document.querySelectorAll('main.markdown-export h2, main.markdown-export h3').forEach(function (heading) {
      if (!heading.id) heading.id = slugify(heading.textContent || "", used);
      var anchor = document.createElement("a");
      anchor.className = "heading-anchor";
      anchor.href = "#" + heading.id;
      anchor.setAttribute("aria-label", "链接到本节");
      anchor.textContent = "#";
      heading.appendChild(anchor);
    });
  }

  function setupToc() {
    var main = document.querySelector("main.markdown-export");
    var headings = Array.prototype.slice.call(document.querySelectorAll("main.markdown-export h2, main.markdown-export h3"));
    if (!main || headings.length < 3) return;

    var details = document.createElement("details");
    details.className = "doc-toc";
    details.open = window.matchMedia("(min-width: 900px)").matches;

    var summary = document.createElement("summary");
    summary.textContent = "目录";
    details.appendChild(summary);

    var nav = document.createElement("nav");
    nav.setAttribute("aria-label", "文档目录");
    headings.forEach(function (heading) {
      var link = document.createElement("a");
      link.href = "#" + heading.id;
      link.className = "toc-" + heading.tagName.toLowerCase();
      link.textContent = heading.textContent.replace(/#$/, "").trim();
      nav.appendChild(link);
    });
    details.appendChild(nav);
    main.insertBefore(details, main.firstElementChild ? main.firstElementChild.nextSibling : null);
  }

  function copyText(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(text);
    }
    var input = document.createElement("textarea");
    input.value = text;
    input.setAttribute("readonly", "");
    input.style.position = "fixed";
    input.style.opacity = "0";
    document.body.appendChild(input);
    input.select();
    var ok = document.execCommand("copy");
    document.body.removeChild(input);
    return ok ? Promise.resolve() : Promise.reject(new Error("copy failed"));
  }

  function setupCodeTools() {
    document.querySelectorAll("pre").forEach(function (pre) {
      if (pre.dataset.tools === "true") return;
      var code = pre.querySelector("code");
      if (!code) return;
      pre.dataset.tools = "true";
      pre.classList.add("code-block");

      var tools = document.createElement("div");
      tools.className = "code-tools";

      var language = document.createElement("span");
      language.className = "code-language";
      var langClass = Array.prototype.find.call(code.classList, function (name) {
        return name.indexOf("language-") === 0;
      });
      language.textContent = langClass ? langClass.replace("language-", "").toUpperCase() : "CODE";

      var button = document.createElement("button");
      button.className = "copy-code";
      button.type = "button";
      button.textContent = "复制";
      button.addEventListener("click", function () {
        copyText(code.textContent || "").then(function () {
          button.textContent = "已复制";
          window.setTimeout(function () { button.textContent = "复制"; }, 1400);
        }, function () {
          button.textContent = "失败";
          window.setTimeout(function () { button.textContent = "复制"; }, 1400);
        });
      });

      tools.appendChild(language);
      tools.appendChild(button);
      pre.appendChild(tools);
    });
  }

  function setupBackToTop() {
    var button = document.createElement("button");
    button.className = "back-to-top";
    button.type = "button";
    button.textContent = "↑";
    button.setAttribute("aria-label", "返回顶部");
    button.addEventListener("click", function () {
      window.scrollTo({ top: 0, behavior: "smooth" });
    });
    document.body.appendChild(button);

    function update() {
      button.classList.toggle("visible", window.scrollY > 360);
    }
    window.addEventListener("scroll", update, { passive: true });
    update();
  }

  function isDocHref(href) {
    if (!href) return false;
    return /\.html($|#)/i.test(href) && href.indexOf("://") === -1;
  }

  /** 将内部文档链接标成按钮，并把「相关文档」段落收成导航条 */
  function setupDocLinks() {
    var main = document.querySelector("main.markdown-export") || document.body;
    main.querySelectorAll('a[href]').forEach(function (a) {
      if (!isDocHref(a.getAttribute("href"))) return;
      if (a.classList.contains("heading-anchor")) return;
      a.classList.add("doc-link");
    });

    main.querySelectorAll("p").forEach(function (p) {
      if (p.closest(".doc-nav")) return;
      var links = Array.prototype.filter.call(p.querySelectorAll("a.doc-link"), function (a) {
        return isDocHref(a.getAttribute("href"));
      });
      if (links.length < 1) return;

      // 段落里几乎只有文档链接（允许 · / 、 见 相关 等提示文字）
      var clone = p.cloneNode(true);
      clone.querySelectorAll("a.doc-link").forEach(function (a) { a.remove(); });
      var leftover = (clone.textContent || "")
        .replace(/[\s·•、，,。:：→\-–—|/\\相关文档见详文完整说明列表]/g, "");
      if (leftover.length > 8 && links.length < 2) return;

      var nav = document.createElement("nav");
      nav.className = "doc-nav";
      nav.setAttribute("aria-label", "相关文档");

      var label = document.createElement("span");
      label.className = "doc-nav-label";
      label.textContent = "相关文档";
      nav.appendChild(label);

      links.forEach(function (a) {
        nav.appendChild(a);
      });
      p.parentNode.replaceChild(nav, p);
    });
  }

  function initDocs() {
    applyHighlighting();
    setupHeadings();
    setupToc();
    setupCodeTools();
    setupDocLinks();
    setupBackToTop();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initDocs);
  } else {
    initDocs();
  }
})();
