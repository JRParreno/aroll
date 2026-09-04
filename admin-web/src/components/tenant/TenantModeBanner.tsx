import {
  DEMO_BANNER_BODY,
  DEMO_BANNER_TITLE,
  DEVTEST_BANNER_BODY,
  DEVTEST_BANNER_TITLE,
  useTenantMode,
} from "@/lib/tenantMode";

export function TenantModeBanner() {
  const { isDemo, isInternalTest, businessName } = useTenantMode();

  if (isDemo) {
    return (
      <div
        className="border-b border-amber-200 bg-amber-50 px-5 py-2.5 sm:px-8"
        data-testid="tenant-mode-banner"
        data-tenant-mode="demo"
      >
        <div className="mx-auto max-w-6xl">
          <p className="text-[11px] font-semibold uppercase tracking-[0.14em] text-amber-900">
            {DEMO_BANNER_TITLE}
          </p>
          <p className="text-sm font-medium text-amber-950">
            {businessName || "AROLL+ Demo Café"}
          </p>
          <p className="text-xs leading-5 text-amber-800">{DEMO_BANNER_BODY}</p>
        </div>
      </div>
    );
  }

  if (isInternalTest) {
    return (
      <div
        className="border-b border-sky-200 bg-sky-50 px-5 py-2.5 sm:px-8"
        data-testid="tenant-mode-banner"
        data-tenant-mode="internal-test"
      >
        <div className="mx-auto max-w-6xl">
          <p className="text-[11px] font-semibold uppercase tracking-[0.14em] text-sky-900">
            {DEVTEST_BANNER_TITLE}
          </p>
          <p className="text-sm font-medium text-sky-950">
            {businessName || "AROLL+ Dev Lab"}
          </p>
          <p className="text-xs leading-5 text-sky-800">{DEVTEST_BANNER_BODY}</p>
        </div>
      </div>
    );
  }

  return null;
}
