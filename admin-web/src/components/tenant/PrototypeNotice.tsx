import {
  PROTOTYPE_NOTICE_BODY,
  PROTOTYPE_NOTICE_TITLE,
  useTenantMode,
} from "@/lib/tenantMode";

export function PrototypeNotice() {
  const { isDemo } = useTenantMode();
  if (!isDemo) return null;
  return (
    <section
      className="rounded-2xl border border-amber-200 bg-amber-50 p-4"
      data-testid="prototype-notice"
    >
      <p className="text-sm font-semibold text-amber-950">{PROTOTYPE_NOTICE_TITLE}</p>
      <p className="mt-1 text-sm leading-6 text-amber-900">{PROTOTYPE_NOTICE_BODY}</p>
    </section>
  );
}
