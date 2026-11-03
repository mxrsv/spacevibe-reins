import { ArrowRight, ArrowUpRight } from "lucide-react";
import type { ReactNode } from "react";

type Variant = "solid" | "ghost";

interface ButtonLinkProps {
  readonly href: string;
  readonly variant?: Variant;
  readonly external?: boolean;
  readonly size?: "sm" | "md";
  readonly className?: string;
  readonly children: ReactNode;
}

const BASE =
  "group inline-flex items-center gap-2 rounded-ctl whitespace-nowrap font-medium leading-none tracking-[-0.005em] no-underline transition-[background-color,border-color,color] duration-150 ease-out";

const VARIANT: Record<Variant, string> = {
  solid: "bg-accent text-white border border-transparent hover:bg-accent-hover",
  ghost: "bg-transparent text-ink-1 border border-edge-strong hover:border-edge-hover hover:text-ink-0",
};

const SIZE = {
  sm: "h-9 px-4 text-sec",
  md: "h-11 px-5 text-body",
} as const;

/** One link styled as a button. The arrow slides 2px on hover; nothing else moves. */
export function ButtonLink({ href, variant = "solid", external = false, size = "sm", className = "", children }: ButtonLinkProps) {
  const Arrow = external ? ArrowUpRight : ArrowRight;
  return (
    <a
      href={href}
      className={`${BASE} ${VARIANT[variant]} ${SIZE[size]} ${className}`}
      {...(external ? { target: "_blank", rel: "noopener noreferrer" } : {})}
    >
      <span>{children}</span>
      <Arrow
        size={14}
        aria-hidden="true"
        className="transition-transform duration-150 ease-out group-hover:translate-x-0.5"
      />
    </a>
  );
}
