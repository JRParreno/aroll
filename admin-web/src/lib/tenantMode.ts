import { useQuery } from "@tanstack/react-query";
import { getMe, type UserMe } from "@/lib/api";
import { ME_QUERY_KEY } from "@/lib/authSession";

/** Session flags only — never from query params or localStorage. */
export function sessionIsDemo(me?: Pick<UserMe, "is_demo"> | null): boolean {
  return me?.is_demo === true;
}

export function sessionIsInternalTest(
  me?: Pick<UserMe, "is_internal_test"> | null
): boolean {
  return me?.is_internal_test === true;
}

export function useTenantMode() {
  const { data: me } = useQuery({
    queryKey: ME_QUERY_KEY,
    queryFn: getMe,
  });
  return {
    me,
    isDemo: sessionIsDemo(me),
    isInternalTest: sessionIsInternalTest(me),
    businessName: me?.business_name ?? "",
  };
}

export const DEMO_BANNER_TITLE = "DEMO MODE";
export const DEMO_BANNER_BODY =
  "AROLL+ Demo Café. All records shown are simulated/demo data.";
export const DEVTEST_BANNER_TITLE = "DEVELOPER TEST MODE";
export const DEVTEST_BANNER_BODY =
  "Internal technical testing only. Not for defense/research demonstration.";
export const PROTOTYPE_NOTICE_TITLE = "Prototype Notice";
export const PROTOTYPE_NOTICE_BODY =
  "This demonstration uses simulated employee, attendance, payroll, biometric, and workplace-location data. It is not used for actual employment decisions, disciplinary action, or salary payment.";
export const PAYSLIP_SAMPLE_LINE_1 = "SAMPLE — DEMONSTRATION ONLY";
export const PAYSLIP_SAMPLE_LINE_2 = "NOT FOR ACTUAL SALARY PAYMENT";
export const RESEARCH_ATTESTATION =
  "I confirm that I am 18 years of age or older and understand that participation in the research evaluation is voluntary.";
export const RESEARCH_VOLUNTARY =
  "Participation in the research evaluation is voluntary. Choosing not to participate will not affect employment, work schedules, compensation, benefits, or your relationship with management. This notice is informational and does not itself guarantee employment protections.";

export const RESEARCH_ACK_STORAGE_KEY = "aroll_research_eval_ack";
