import type { LucideIcon } from "lucide-react";
import { Link } from "react-router-dom";
import { cn } from "@/lib/utils";
import { ShimmerStatCard } from "@/components/ui/shimmer";

export type StatCardTone = "navy" | "green" | "purple" | "amber";

const tones: Record<
  StatCardTone,
  { card: string; icon: string; value: string; muted: string; link: string }
> = {
  navy: {
    card: "bg-[#E7F0FA] border-[#D5E4F4]",
    icon: "bg-[#1E3A5F] text-white",
    value: "text-[#1E3A5F]",
    muted: "text-[#5B7390]",
    link: "text-[#1E3A5F]",
  },
  green: {
    card: "bg-[#E8F6EE] border-[#D3EBDC]",
    icon: "bg-[#2F7D4A] text-white",
    value: "text-[#215C36]",
    muted: "text-[#4F7A5F]",
    link: "text-[#215C36]",
  },
  purple: {
    card: "bg-[#F1EAF8] border-[#E3D7F0]",
    icon: "bg-[#6B4FA0] text-white",
    value: "text-[#4C3480]",
    muted: "text-[#6F5B8F]",
    link: "text-[#4C3480]",
  },
  amber: {
    card: "bg-[#F8EEE6] border-[#EEDFCE]",
    icon: "bg-[#C56A2D] text-white",
    value: "text-[#9A4E1C]",
    muted: "text-[#8A684C]",
    link: "text-[#9A4E1C]",
  },
};

type StatCardProps = {
  label: string;
  value: number | string;
  subtitle?: string;
  to?: string;
  linkLabel?: string;
  icon?: LucideIcon;
  tone?: StatCardTone;
  className?: string;
  loading?: boolean;
};

export function StatCard({
  label,
  value,
  subtitle,
  to,
  linkLabel,
  icon: Icon,
  tone = "navy",
  className,
  loading,
}: StatCardProps) {
  const palette = tones[tone];

  if (loading) {
    return <ShimmerStatCard className={cn(palette.card, className)} />;
  }

  const body = (
    <>
      <div className="flex items-center gap-3">
        {Icon ? (
          <span
            className={cn(
              "flex h-10 w-10 shrink-0 items-center justify-center rounded-full",
              palette.icon
            )}
          >
            <Icon className="h-[18px] w-[18px]" strokeWidth={2} />
          </span>
        ) : null}
        <p
          className={cn(
            "min-w-0 text-[11px] font-semibold uppercase tracking-[0.08em]",
            palette.muted
          )}
        >
          {label}
        </p>
      </div>
      <p
        className={cn(
          "mt-4 text-[1.75rem] font-semibold leading-none tracking-tight",
          palette.value
        )}
      >
        {value}
      </p>
      <p className={cn("mt-2 min-h-4 truncate text-xs leading-4", palette.muted)}>
        {subtitle || "\u00A0"}
      </p>
      <p className={cn("mt-auto pt-3 min-h-4 truncate text-xs font-medium leading-4", palette.link)}>
        {to ? `${linkLabel ?? "View details"} →` : "\u00A0"}
      </p>
    </>
  );

  const cardClassName = cn(
    "flex h-full min-h-[10.25rem] flex-col rounded-[1.15rem] border px-4 py-4 transition hover:shadow-[0_6px_16px_rgba(16,35,58,0.08)]",
    palette.card,
    to && "transition hover:brightness-[0.99] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#284B73]/25",
    className
  );

  if (to) {
    return (
      <Link to={to} className={cardClassName}>
        {body}
      </Link>
    );
  }

  return <div className={cardClassName}>{body}</div>;
}
