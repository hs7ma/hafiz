/* Hafiz geometric parchment — header, octagon select, split, scroll progress */
(() => {
  "use strict";

  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  const initHeader = () => {
    const header = document.querySelector("[data-header]");
    const nav = document.getElementById("site-nav");
    const toggle = document.querySelector("[data-nav-toggle]");

    if (header) {
      const onScroll = () => {
        header.classList.toggle("is-scrolled", window.scrollY > 8);
        const bar = document.querySelector(".scroll-progress");
        if (bar) {
          const max = document.documentElement.scrollHeight - window.innerHeight;
          const p = max > 0 ? window.scrollY / max : 0;
          bar.style.transform = `scaleX(${Math.min(1, Math.max(0, p))})`;
        }
      };
      onScroll();
      window.addEventListener("scroll", onScroll, { passive: true });
    }

    if (!nav || !toggle) return;
    const close = () => {
      nav.classList.remove("is-open");
      toggle.setAttribute("aria-expanded", "false");
    };
    toggle.addEventListener("click", () => {
      const open = nav.classList.toggle("is-open");
      toggle.setAttribute("aria-expanded", open ? "true" : "false");
    });
    nav.querySelectorAll("a").forEach((a) => a.addEventListener("click", close));
    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape") close();
    });
  };

  const initStamps = () => {
    const panels = document.querySelectorAll(".octagon-panel, .stamp--panel");
    panels.forEach((panel) => {
      const activate = () => {
        panels.forEach((p) => {
          p.classList.remove("is-active");
          p.classList.remove("is-inked");
        });
        panel.classList.add("is-active");
        panel.classList.add("is-inked");
      };
      panel.addEventListener("click", activate);
      panel.addEventListener("keydown", (e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          activate();
        }
      });
    });
  };

  const initSplit = () => {
    const split = document.querySelector("[data-split]");
    const handle = document.querySelector("[data-split-handle]");
    if (!split || !handle) return;

    // Desktop: visual emphasis only (equal panes). Mobile stacks via CSS.
    // Drag rebalances flex feel via class — keep both panes fully readable.
    let dragging = false;
    const onDown = () => {
      dragging = true;
      handle.setAttribute("aria-pressed", "true");
    };
    const onUp = () => {
      dragging = false;
      handle.setAttribute("aria-pressed", "false");
    };
    handle.addEventListener("pointerdown", (e) => {
      handle.setPointerCapture(e.pointerId);
      onDown();
    });
    handle.addEventListener("pointerup", onUp);
    handle.addEventListener("pointercancel", onUp);
    handle.addEventListener("pointermove", (e) => {
      if (!dragging || window.matchMedia("(max-width: 720px)").matches) return;
      const rect = split.getBoundingClientRect();
      if (!rect.width) return;
      // RTL: pointer from right
      const fromStart = (rect.right - e.clientX) / rect.width;
      const clamped = Math.min(0.72, Math.max(0.28, fromStart));
      const before = split.querySelector(".split__pane--before");
      const after = split.querySelector(".split__pane--after");
      if (before && after) {
        before.style.flex = String(clamped);
        after.style.flex = String(1 - clamped);
        split.style.display = "flex";
        handle.style.flex = "0 0 1.1rem";
        before.style.minWidth = "0";
        after.style.minWidth = "0";
      }
    });
  };

  const initReveal = () => {
    if (reduce || !("IntersectionObserver" in window)) return;
    document.documentElement.dataset.revealReady = "";
    const nodes = document.querySelectorAll(
      ".section__title, .section__lead, .octagon-panel, .stamp--panel, .path-steps__item, .path-rail__item, .faq-item, .split"
    );
    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          const el = entry.target;
          el.style.transition = "opacity 0.55s var(--ease, ease), transform 0.55s var(--ease, ease)";
          el.style.opacity = "1";
          el.style.transform = "none";
          io.unobserve(el);
        });
      },
      { threshold: 0.12, rootMargin: "0px 0px -8% 0px" }
    );
    nodes.forEach((n, i) => {
      n.style.transitionDelay = `${Math.min(i % 4, 3) * 0.06}s`;
      io.observe(n);
    });
    // Safety: never leave content invisible
    window.setTimeout(() => {
      nodes.forEach((n) => {
        n.style.opacity = "1";
        n.style.transform = "none";
      });
    }, 2800);
  };

  const boot = () => {
    initHeader();
    initStamps();
    initSplit();
    initReveal();
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
