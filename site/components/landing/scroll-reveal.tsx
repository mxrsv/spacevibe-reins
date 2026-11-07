"use client";

import { useEffect } from "react";

export const LANDING_ROOT_ID = "spacevibe-landing";

/**
 * Adds `.in` to every `[data-reveal]` as it enters the viewport. Renders nothing
 * and runs over the server-rendered DOM, so the page stays a Server Component.
 *
 * The root is flagged `data-motion-ready` only once the observer exists; CSS hides
 * `[data-reveal]` only under that flag, so a bundle that never arrives (blocked
 * script, 404 chunk) leaves the page fully visible.
 */
export function ScrollReveal() {
  useEffect(() => {
    const root = document.getElementById(LANDING_ROOT_ID);
    if (!root || typeof IntersectionObserver === "undefined") return;

    const targets = Array.from(root.querySelectorAll("[data-reveal]"));
    if (targets.length === 0) return;

    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) continue;
          entry.target.classList.add("in");
          observer.unobserve(entry.target);
        }
      },
      { threshold: 0.12, rootMargin: "0px 0px -8% 0px" },
    );

    for (const node of targets) observer.observe(node);
    root.setAttribute("data-motion-ready", "");

    return () => {
      observer.disconnect();
      root.removeAttribute("data-motion-ready");
    };
  }, []);

  return null;
}
