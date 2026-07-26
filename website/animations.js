/* Hafiz editorial — scroll progress, atmosphere scenes, soft reveals */
(() => {
  "use strict";

  document.documentElement.classList.add("js");

  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  const initProgress = () => {
    const bar = document.querySelector(".scroll-progress");
    if (!bar) return;
    const onScroll = () => {
      const max = document.documentElement.scrollHeight - window.innerHeight;
      const p = max > 0 ? window.scrollY / max : 0;
      bar.style.transform = `scaleX(${Math.min(1, Math.max(0, p))})`;
    };
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
  };

  const initAtmosphere = () => {
    const root = document.querySelector("[data-atmosphere]");
    if (!root) return;

    const scenes = [...root.querySelectorAll(".page-atmosphere__img")];
    if (!scenes.length) return;

    const sections = [...document.querySelectorAll("[data-atmosphere-scene]")];
    let active = -1;

    const setScene = (index) => {
      const next = Math.max(0, Math.min(scenes.length - 1, Number(index) || 0));
      if (next === active) return;
      active = next;
      scenes.forEach((img, i) => {
        img.classList.toggle("is-active", i === active);
      });
    };

    const pickScene = () => {
      if (!sections.length) {
        const max = document.documentElement.scrollHeight - window.innerHeight;
        const p = max > 0 ? window.scrollY / max : 0;
        setScene(Math.round(p * (scenes.length - 1)));
        return;
      }

      const focusY = window.innerHeight * 0.32;
      let bestSection = sections[0];
      let bestScore = Infinity;

      sections.forEach((section) => {
        const rect = section.getBoundingClientRect();
        // Prefer the section whose vertical span covers the focus line
        if (rect.top <= focusY && rect.bottom >= focusY) {
          bestSection = section;
          bestScore = -1;
          return;
        }
        if (bestScore < 0) return;
        const dist = Math.min(Math.abs(rect.top - focusY), Math.abs(rect.bottom - focusY));
        if (dist < bestScore) {
          bestScore = dist;
          bestSection = section;
        }
      });

      setScene(bestSection.getAttribute("data-atmosphere-scene"));
    };

    if (reduce) {
      setScene(0);
      return;
    }

    let ticking = false;
    const onScroll = () => {
      if (ticking) return;
      ticking = true;
      window.requestAnimationFrame(() => {
        pickScene();
        ticking = false;
      });
    };

    setScene(0);
    pickScene();
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onScroll, { passive: true });
  };

  const initReveals = () => {
    const nodes = [...document.querySelectorAll("[data-reveal]")];
    if (!nodes.length) return;

    const reveal = (n) => n.classList.add("is-in");

    if (reduce || !("IntersectionObserver" in window)) {
      nodes.forEach(reveal);
      return;
    }

    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          reveal(entry.target);
          io.unobserve(entry.target);
        });
      },
      { rootMargin: "0px 0px -4% 0px", threshold: 0.08 }
    );

    nodes.forEach((n) => {
      const rect = n.getBoundingClientRect();
      if (rect.top < window.innerHeight * 0.96 && rect.bottom > 0) {
        reveal(n);
        return;
      }
      io.observe(n);
    });

    window.setTimeout(() => nodes.forEach(reveal), 1800);
  };

  initProgress();
  initAtmosphere();
  initReveals();
})();
