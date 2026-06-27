import { Link } from "react-router-dom";
import { cn } from "@/lib/utils";
import { ShimmerStatCard } from "@/components/ui/shimmer";

type StatCardProps = {
  label: string;
  value: number | string;
  subtitle?: string;
  to?: string;
  className?: string;
  loading?: boolean;
};

export function StatCard({ label, value, subtitle, to, className, loading }: StatCardProps) {
  if (loading) {
    return <ShimmerStatCard className={className} />;
  }

  const content = (
    <>
      <p className="text-sm font-medium opacity-85">{label}</p>
      <p className="mt-3 text-3xl font-semibold tracking-tight">{value}</p>
      {subtitle && (
        <p className="mt-2 text-xs opacity-75">{subtitle}</p>
      )}
    </>
  );

  const cardClassName = cn(
    "rounded-2xl border border-white/20 px-6 py-5 text-white shadow-sm",
    to && "block transition-all hover:-translate-y-0.5 hover:shadow-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#284B73]/30",
    className
  );

  if (to) {
    return (
      <Link to={to} className={cardClassName}>
        {content}
      </Link>
    );
  }

  return <div className={cardClassName}>{content}</div>;
}
