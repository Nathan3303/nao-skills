/* nao-skills 门户单页 —— 仅两件事：复制安装命令、锚点导航当前段标记。
   无 JS 时全内容可见、命令可手选；本文件不发起任何网络请求。 */
(function () {
  'use strict';

  var IDLE = '复制';
  var DONE = '已复制 ✓';
  var FAIL = '已选中，请按 ⌘/Ctrl+C';
  var HOLD_MS = 1800;

  var cmd = document.getElementById('install-cmd');
  var btn = document.getElementById('copy-btn');
  var status = document.getElementById('copy-status');

  if (cmd && btn && status) {
    setupCopy();
  }

  function setupCopy() {
    var timer = null;

    btn.addEventListener('click', function () {
      copyText(cmd.textContent.trim()).then(function (ok) {
        if (ok) {
          setState(DONE, '已复制安装命令，回终端粘贴即可。');
        } else {
          setState(FAIL, '浏览器不允许自动复制，命令已选中，请按 ⌘ 或 Ctrl 加 C 复制。');
          selectCommand();
        }
        clearTimeout(timer);
        timer = setTimeout(reset, HOLD_MS);
      });
    });

    function setState(label, note) {
      btn.textContent = label;
      status.textContent = note;
    }

    function reset() {
      btn.textContent = IDLE;
      status.textContent = '';
    }

    function selectCommand() {
      var range = document.createRange();
      range.selectNodeContents(cmd);
      var selection = window.getSelection();
      if (!selection) {
        return;
      }
      selection.removeAllRanges();
      selection.addRange(range);
    }
  }

  /* 依次尝试异步剪贴板与旧式 execCommand；两者都失败才算失败。 */
  function copyText(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(text).then(
        function () { return true; },
        function () { return legacyCopy(text); }
      );
    }
    return Promise.resolve(legacyCopy(text));
  }

  function legacyCopy(text) {
    var area = document.createElement('textarea');
    var ok = false;
    area.value = text;
    area.setAttribute('readonly', '');
    area.style.position = 'fixed';
    area.style.top = '0';
    area.style.left = '-9999px';
    document.body.appendChild(area);
    area.select();
    try {
      ok = document.execCommand('copy');
    } catch (err) {
      ok = false;
    }
    document.body.removeChild(area);
    return ok;
  }

  /* 锚点导航：当前段加 aria-current；不支持 IntersectionObserver 时仅失去高亮。 */
  (function highlightCurrentSection() {
    if (!('IntersectionObserver' in window)) {
      return;
    }
    var links = Array.prototype.slice.call(document.querySelectorAll('.nav a[href^="#"]'));
    var sections = [];
    var visible = {};

    links.forEach(function (link) {
      var target = document.getElementById(link.getAttribute('href').slice(1));
      if (target) {
        sections.push(target);
      }
    });

    if (!sections.length) {
      return;
    }

    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        visible[entry.target.id] = entry.isIntersecting;
      });
      var active = sections.filter(function (section) {
        return visible[section.id];
      })[0];
      links.forEach(function (link) {
        if (active && link.getAttribute('href') === '#' + active.id) {
          link.setAttribute('aria-current', 'true');
        } else {
          link.removeAttribute('aria-current');
        }
      });
    }, { rootMargin: '-45% 0px -50% 0px' });

    sections.forEach(function (section) {
      observer.observe(section);
    });
  })();
})();
