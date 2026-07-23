/* Hafiz website — animations
   Safe reveals with explicit end states, particles, parallax.
   Respects prefers-reduced-motion. Never leaves content invisible.
*/

(() => {
  "use strict";

  const prefersReduce = window.matchMedia(
    "(prefers-reduced-motion: reduce)"
  ).matches;

  const showAll = () => {
    document
      .querySelectorAll(
        "[data-reveal-child], [data-reveal] h2, [data-reveal] .section__lead, .showcase-hero__art, .feature-card__art, .footer, .hero__mark, .hero__brand, .hero__lead, .hero__actions .btn"
      )
      .forEach((el) => {
        el.style.opacity = "1";
        el.style.transform = "none";
      });
  };

  /* ---------- Hero particles ---------- */
  const initParticles = () => {
    const canvas = document.querySelector(".hero__particles");
    if (!canvas || prefersReduce) return;

    const ctx = canvas.getContext("2d", { alpha: true });
    if (!ctx) return;

    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    let width = 0;
    let height = 0;
    let particles = [];
    let raf = 0;
    let last = performance.now();

    const PALETTE = [
      "rgba(194, 161, 90, 0.85)",
      "rgba(212, 185, 120, 0.7)",
      "rgba(31, 77, 58, 0.55)",
      "rgba(247, 241, 230, 0.85)",
    ];

    const spawn = () => ({
      x: Math.random() * width,
      y: Math.random() * height,
      r: Math.random() * 1.8 + 0.4,
      vy: -(Math.random() * 0.25 + 0.05),
      vx: (Math.random() - 0.5) * 0.12,
      a: Math.random() * 0.6 + 0.3,
      twinkle: Math.random() * Math.PI * 2,
      color: PALETTE[Math.floor(Math.random() * PALETTE.length)],
    });

    const resize = () => {
      const rect = canvas.getBoundingClientRect();
      width = rect.width;
      height = rect.height;
      if (width < 1 || height < 1) return;
      canvas.width = width * dpr;
      canvas.height = height * dpr;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      const count = Math.min(
        60,
        Math.max(18, Math.round((width * height) / 28000))
      );
      particles = new Array(count).fill(0).map(() => spawn());
    };

    const draw = (now) => {
      const dt = Math.min(48, now - last);
      last = now;
      ctx.clearRect(0, 0, width, height);

      for (const p of particles) {
        p.twinkle += dt * 0.0025;
        const alpha = p.a * (0.55 + 0.45 * Math.sin(p.twinkle));
        p.x += p.vx * dt * 0.06;
        p.y += p.vy * dt * 0.06;
        if (p.y < -10) p.y = height + 10;
        if (p.x < -10) p.x = width + 10;
        if (p.x > width + 10) p.x = -10;

        const parts = p.color.match(/[\d.]+/g) || [];
        ctx.beginPath();
        ctx.fillStyle = `rgba(${parts[0]}, ${parts[1]}, ${parts[2]}, ${alpha})`;
        ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
        ctx.fill();
      }
      raf = requestAnimationFrame(draw);
    };

    const start = () => {
      if (raf || prefersReduce) return;
      last = performance.now();
      raf = requestAnimationFrame(draw);
    };
    const stop = () => {
      cancelAnimationFrame(raf);
      raf = 0;
    };

    resize();
    start();

    let resizeTimer;
    window.addEventListener("resize", () => {
      clearTimeout(resizeTimer);
      resizeTimer = setTimeout(resize, 150);
    });

    if ("IntersectionObserver" in window) {
      const io = new IntersectionObserver(
        ([entry]) => (entry.isIntersecting ? start() : stop()),
        { threshold: 0 }
      );
      io.observe(canvas);
    }
  };

  /* ---------- Mouse parallax on hero blobs ---------- */
  const initParallax = () => {
    if (prefersReduce) return;
    const hero = document.querySelector(".hero");
    const blobs = document.querySelectorAll(".hero__blob");
    if (!hero || !blobs.length) return;

    let rx = 0;
    let ry = 0;
    let tx = 0;
    let ty = 0;
    let raf = 0;

    const onMove = (e) => {
      const rect = hero.getBoundingClientRect();
      if (!rect.width || !rect.height) return;
      tx = ((e.clientX - rect.left) / rect.width - 0.5) * 16;
      ty = ((e.clientY - rect.top) / rect.height - 0.5) * 16;
    };

    const tick = () => {
      rx += (tx - rx) * 0.06;
      ry += (ty - ry) * 0.06;
      blobs.forEach((b, i) => {
        const k = i === 0 ? 0.6 : -0.6;
        // Use `translate` so CSS `transform` animations (blob-drift) still apply
        b.style.translate = `${rx * k}px ${ry * k}px`;
      });
      raf = requestAnimationFrame(tick);
    };

    window.addEventListener("mousemove", onMove, { passive: true });
    raf = requestAnimationFrame(tick);
  };

  /* ---------- GSAP ---------- */
  const initGSAP = () => {
    if (prefersReduce || typeof gsap === "undefined") {
      showAll();
      return;
    }

    try {
      if (typeof ScrollTrigger !== "undefined") {
        gsap.registerPlugin(ScrollTrigger);
      }

      // Keep content visible — animate only movement, never opacity:0
      gsap.set(
        [".hero__mark", ".hero__brand", ".hero__lead", ".hero__actions .btn"],
        { y: 20 }
      );

      const tl = gsap.timeline({ defaults: { ease: "power3.out" } });
      tl.to(".hero__mark", { y: 0, duration: 0.95 })
        .to(".hero__brand", { y: 0, duration: 0.7 }, "-=0.55")
        .to(".hero__lead", { y: 0, duration: 0.65 }, "-=0.4")
        .to(
          ".hero__actions .btn",
          { y: 0, stagger: 0.1, duration: 0.55 },
          "-=0.35"
        );

      if (typeof ScrollTrigger !== "undefined") {
        gsap.to(".hero__mark", {
          yPercent: 12,
          ease: "none",
          scrollTrigger: {
            trigger: ".hero",
            start: "top top",
            end: "bottom top",
            scrub: true,
          },
        });

        document.querySelectorAll("[data-reveal]").forEach((section) => {
          const heading = section.querySelector("h2");
          const lead = section.querySelector(".section__lead");
          const children = section.querySelectorAll("[data-reveal-child]");
          const arts = section.querySelectorAll(
            ".showcase-hero__art, .feature-card__art"
          );

          if (heading) gsap.set(heading, { y: 18 });
          if (lead) gsap.set(lead, { y: 14 });
          if (children.length) gsap.set(children, { y: 18 });
          if (arts.length) gsap.set(arts, { scale: 0.96 });

          const tl2 = gsap.timeline({
            scrollTrigger: {
              trigger: section,
              start: "top 80%",
              once: true,
            },
            defaults: { ease: "power3.out" },
          });

          if (heading) {
            tl2.to(heading, { y: 0, duration: 0.65 });
          }
          if (lead) {
            tl2.to(lead, { y: 0, duration: 0.55 }, "-=0.4");
          }
          if (arts.length) {
            tl2.to(
              arts,
              { scale: 1, duration: 0.7, stagger: 0.08 },
              "-=0.35"
            );
          }
          if (children.length) {
            tl2.to(
              children,
              { y: 0, stagger: 0.09, duration: 0.6 },
              "-=0.35"
            );
          }
        });

        const bar = document.querySelector(".scroll-progress");
        if (bar) {
          gsap.fromTo(
            bar,
            { scaleX: 0 },
            {
              scaleX: 1,
              ease: "none",
              scrollTrigger: {
                start: 0,
                end: "max",
                scrub: 0.25,
              },
            }
          );
        }

        const footer = document.querySelector(".footer");
        if (footer) {
          gsap.fromTo(
            footer,
            { y: 10 },
            {
              y: 0,
              duration: 0.6,
              ease: "power2.out",
              scrollTrigger: {
                trigger: footer,
                start: "top 95%",
                once: true,
              },
            }
          );
        }

        document.querySelectorAll(".divider").forEach((divider) => {
          gsap.fromTo(
            divider,
            { opacity: 0.35 },
            {
              opacity: 1,
              duration: 0.8,
              ease: "power2.out",
              scrollTrigger: {
                trigger: divider,
                start: "top 95%",
                once: true,
              },
            }
          );
        });
      } else {
        showAll();
      }

      window.setTimeout(() => {
        document
          .querySelectorAll(
            "[data-reveal] h2, [data-reveal] .section__lead, [data-reveal-child], .hero__brand, .hero__lead, .hero__actions .btn"
          )
          .forEach((el) => {
            if (getComputedStyle(el).opacity === "0") {
              el.style.opacity = "1";
              el.style.transform = "none";
            }
          });
      }, 3000);
    } catch (err) {
      console.error("Hafiz animations failed:", err);
      showAll();
    }
  };

  const boot = () => {
    document.documentElement.classList.add("js-anim");
    initParticles();
    initParallax();
    // Wait a tick so deferred GSAP globals exist
    const tryInit = () => {
      if (typeof gsap !== "undefined" || prefersReduce) {
        initGSAP();
        return;
      }
      // CDN still loading
      let tries = 0;
      const id = window.setInterval(() => {
        tries += 1;
        if (typeof gsap !== "undefined" || tries > 40) {
          window.clearInterval(id);
          initGSAP();
        }
      }, 50);
    };
    tryInit();
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
