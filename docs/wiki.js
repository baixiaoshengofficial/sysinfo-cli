(function () {
  'use strict';

  var lang = localStorage.getItem('sysinfo-lang') ||
    ((navigator.language || '').startsWith('zh') ? 'zh' : 'en');

  var sidebar = document.getElementById('sidebar');
  var menuBtn = document.getElementById('menuBtn');

  function pageIdFromHref(href) {
    if (!href) return '';
    var hash = href.indexOf('#');
    return hash >= 0 ? href.slice(hash + 1) : '';
  }

  function getPages() {
    return document.querySelectorAll('main.content > article.page');
  }

  function getNavItems() {
    return document.querySelectorAll('.sidebar-nav .nav-item');
  }

  // --- Language (only update leaf nodes to preserve inner HTML like <code>) ---
  function applyLang(l) {
    lang = l;
    document.documentElement.lang = (l === 'zh') ? 'zh-CN' : 'en';

    document.querySelectorAll('[data-zh]').forEach(function (el) {
      if (el.childElementCount > 0) return;
      var v = el.getAttribute('data-' + l);
      if (v !== null) el.textContent = v;
    });

    document.querySelectorAll('.nav-group').forEach(function (g) {
      g.setAttribute('data-label', g.getAttribute('data-label-' + l) || '');
    });

    document.querySelectorAll('.lang-btn').forEach(function (b) {
      b.textContent = (l === 'zh') ? 'EN' : '中文';
    });

    localStorage.setItem('sysinfo-lang', l);
  }

  document.querySelectorAll('.lang-btn').forEach(function (btn) {
    btn.addEventListener('click', function () {
      applyLang(lang === 'zh' ? 'en' : 'zh');
    });
  });

  // --- Page navigation ---
  function showPage(id) {
    if (!id) id = 'intro';
    var target = document.getElementById(id);
    if (!target || !target.classList.contains('page')) {
      id = 'intro';
      target = document.getElementById('intro');
    }

    getPages().forEach(function (p) {
      var on = (p.id === id);
      p.classList.toggle('active', on);
      p.style.display = on ? 'block' : 'none';
    });

    getNavItems().forEach(function (n) {
      n.classList.toggle('active', pageIdFromHref(n.getAttribute('href')) === id);
    });

    if (location.hash !== '#' + id) {
      history.replaceState(null, '', '#' + id);
    }

    if (sidebar) sidebar.classList.remove('open');
    window.scrollTo(0, 0);
  }

  getNavItems().forEach(function (item) {
    item.addEventListener('click', function (e) {
      e.preventDefault();
      showPage(pageIdFromHref(item.getAttribute('href')));
    });
  });

  window.addEventListener('hashchange', function () {
    showPage(pageIdFromHref(location.hash));
  });

  if (menuBtn && sidebar) {
    menuBtn.addEventListener('click', function () {
      sidebar.classList.toggle('open');
    });
  }

  // Init: hash > intro
  var initial = pageIdFromHref(location.hash);
  showPage(document.getElementById(initial) ? initial : 'intro');
  applyLang(lang);
})();
