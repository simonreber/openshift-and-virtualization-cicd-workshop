/* Workshop theme JS — terminal effects */
(function () {
  'use strict';

  // ── Typed text effect for site title ──────────────────────────────────
  const typed = document.querySelector('.typed');
  if (typed) {
    const text = typed.dataset.text || typed.textContent;
    typed.textContent = '';
    let i = 0;
    const interval = setInterval(() => {
      typed.textContent += text[i++];
      if (i >= text.length) clearInterval(interval);
    }, 55);
  }

  // ── Highlight active nav based on current path ────────────────────────
  const path = window.location.pathname;
  document.querySelectorAll('.nav-link').forEach(link => {
    const href = link.getAttribute('href');
    if (href && href !== '/' && path.startsWith(href)) {
      link.classList.add('active');
    } else if (href === '/' && path === '/') {
      link.classList.add('active');
    }
  });

  // ── Add copy button to code blocks ────────────────────────────────────
  document.querySelectorAll('.post-content pre').forEach(pre => {
    const btn = document.createElement('button');
    btn.textContent = 'copy';
    btn.style.cssText = `
      position: absolute;
      top: 0.6rem;
      right: 0.6rem;
      font-family: 'JetBrains Mono', monospace;
      font-size: 0.68rem;
      background: var(--bg-elevated);
      border: 1px solid var(--border);
      border-radius: 4px;
      color: var(--text-muted);
      padding: 0.2rem 0.55rem;
      cursor: pointer;
      transition: all 0.15s ease;
    `;
    btn.addEventListener('mouseenter', () => { btn.style.color = 'var(--green)'; btn.style.borderColor = 'var(--green)'; });
    btn.addEventListener('mouseleave', () => { btn.style.color = 'var(--text-muted)'; btn.style.borderColor = 'var(--border)'; });
    btn.addEventListener('click', () => {
      const code = pre.querySelector('code');
      navigator.clipboard.writeText(code ? code.textContent : pre.textContent).then(() => {
        btn.textContent = 'copied!';
        btn.style.color = 'var(--green)';
        setTimeout(() => { btn.textContent = 'copy'; btn.style.color = 'var(--text-muted)'; }, 1800);
      });
    });
    pre.style.position = 'relative';
    pre.appendChild(btn);
  });

  // ── Subtle entrance animation for list/card items ─────────────────────
  if ('IntersectionObserver' in window) {
    const obs = new IntersectionObserver((entries) => {
      entries.forEach(e => {
        if (e.isIntersecting) {
          e.target.style.opacity = '1';
          e.target.style.transform = 'translateY(0)';
          obs.unobserve(e.target);
        }
      });
    }, { threshold: 0.1 });

    document.querySelectorAll('.post-card, .list-item, .flow-step, .env-box').forEach((el, i) => {
      el.style.opacity = '0';
      el.style.transform = 'translateY(12px)';
      el.style.transition = `opacity 0.4s ease ${i * 0.06}s, transform 0.4s ease ${i * 0.06}s`;
      obs.observe(el);
    });
  }
})();
