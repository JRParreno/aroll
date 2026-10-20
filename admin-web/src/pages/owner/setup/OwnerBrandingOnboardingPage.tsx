import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { toast } from "sonner";
import { BusinessLogoAndThemeFields } from "@/components/owner/settings/brandingFormFields";
import {
  businessBrandingForSave,
  defaultBusinessBranding,
} from "@/components/owner/settings/brandingDefaults";
import { Button } from "@/components/ui/button";
import {
  completeBrandingOnboarding,
  getBusinessSettings,
  type BusinessBrandingSettings,
} from "@/lib/api";
import { ME_QUERY_KEY } from "@/lib/authSession";
import { wizardPrimaryBtnClass } from "@/components/owner/setup/wizardUi";

export function OwnerBrandingOnboardingPage() {
  const navigate = useNavigate();
  const qc = useQueryClient();
  const [branding, setBranding] =
    useState<BusinessBrandingSettings>(defaultBusinessBranding);

  const { data, isLoading, isError } = useQuery({
    queryKey: ["business-settings"],
    queryFn: getBusinessSettings,
  });

  useEffect(() => {
    if (!data) return;
    setBranding(data.branding ?? defaultBusinessBranding);
  }, [data]);

  async function goToSetup() {
    await qc.invalidateQueries({ queryKey: ME_QUERY_KEY });
    navigate("/owner/setup-wizard", { replace: true });
  }

  const save = useMutation({
    mutationFn: async () => {
      await completeBrandingOnboarding(businessBrandingForSave(branding));
    },
    onSuccess: async () => {
      toast.success("Branding saved");
      qc.invalidateQueries({ queryKey: ["business-settings"] });
      await goToSetup();
    },
    onError: () => toast.error("Could not save branding"),
  });

  const skip = useMutation({
    mutationFn: completeBrandingOnboarding,
    onSuccess: async () => {
      await goToSetup();
    },
    onError: () => toast.error("Could not skip branding"),
  });

  const busy = save.isPending || skip.isPending;

  return (
    <div className="min-h-screen bg-[#F4F6F8] text-[#111827]">
      <div className="mx-auto w-full max-w-3xl px-5 py-8 sm:px-8">
        <p className="text-xs font-semibold uppercase tracking-[0.14em] text-[#6B7280]">
          Step 1 of first login
        </p>
        <h1 className="mt-2 text-2xl font-semibold tracking-tight">
          Business Branding
        </h1>
        <p className="mt-2 text-sm leading-6 text-[#6B7280]">
          Optional logo and brand-color customization. You can skip this and
          change it later in Business Settings.
        </p>

        <div className="mt-6 rounded-2xl border border-slate-200 bg-white p-5 shadow-sm sm:p-6">
          {isLoading ? (
            <p className="text-sm text-[#6B7280]">Loading branding…</p>
          ) : isError || !data ? (
            <p className="text-sm text-red-600">
              Could not load branding. Please try again.
            </p>
          ) : (
            <BusinessLogoAndThemeFields
              branding={branding}
              savedTheme={(data.branding ?? defaultBusinessBranding).theme}
              businessName={data.business_name}
              onChange={setBranding}
            />
          )}
        </div>

        <div className="mt-6 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
          <Button
            type="button"
            variant="ghost"
            className="h-10 rounded-xl"
            disabled={busy}
            onClick={() => skip.mutate()}
          >
            Skip for now
          </Button>
          <Button
            type="button"
            className={wizardPrimaryBtnClass}
            disabled={busy || isLoading || isError}
            onClick={() => save.mutate()}
          >
            {save.isPending ? "Saving…" : "Save and continue"}
          </Button>
        </div>
      </div>
    </div>
  );
}
