import { FOOTER } from "./content";
import { ReinsMark } from "./reins-mark";

/** One row: brand and the four anchors left, GitHub and the year right. */
export function SiteFooter() {
  const year = new Date().getFullYear();
  return (
    <footer className="border-t border-edge py-8">
      <div className="shell flex flex-wrap items-center gap-x-8 gap-y-3">
        <span className="inline-flex items-center gap-2 text-sec font-medium text-ink-1">
          <ReinsMark className="size-4" />
          {FOOTER.brand}
        </span>
        <nav className="flex gap-6 max-md:order-3 max-md:w-full md:mr-auto" aria-label="Sections (footer)">
          {FOOTER.nav.map((link) => (
            <a key={link.href} href={link.href} className="text-sec text-ink-2 no-underline transition-colors duration-150 hover:text-ink-1">
              {link.label}
            </a>
          ))}
        </nav>
        <a
          href={FOOTER.github.href}
          target="_blank"
          rel="noopener noreferrer"
          className="text-sec text-ink-2 no-underline transition-colors duration-150 hover:text-ink-1"
        >
          {FOOTER.github.label}
        </a>
        <span className="text-sec text-ink-2 max-md:ml-auto">
          © {year} {FOOTER.by}
        </span>
      </div>
    </footer>
  );
}
