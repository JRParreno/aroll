import { describe, expect, it } from "vitest";
import {
  SETUP_WIZARD_LEAVE_POLICY_STEP,
  SETUP_WIZARD_STEPS,
  ownerFirstLoginPath,
} from "./ownerFirstLoginPath";

describe("ownerFirstLoginPath", () => {
  it("sends completed owners to the dashboard", () => {
    expect(
      ownerFirstLoginPath({
        setup_completed_at: "2026-01-01T00:00:00Z",
        needs_branding_onboarding: true,
      })
    ).toBe("/owner/dashboard");
  });

  it("sends new owners to branding before setup", () => {
    expect(
      ownerFirstLoginPath({
        setup_completed_at: null,
        needs_branding_onboarding: true,
      })
    ).toBe("/owner/branding-setup");
  });

  it("sends owners who already skipped branding to setup", () => {
    expect(
      ownerFirstLoginPath({
        setup_completed_at: null,
        needs_branding_onboarding: false,
      })
    ).toBe("/owner/setup-wizard");
  });
});

describe("setup wizard leave policy placement", () => {
  it("places Leave Policy immediately after Holiday Management", () => {
    expect(SETUP_WIZARD_STEPS[4]).toBe("Holiday Management");
    expect(SETUP_WIZARD_STEPS[SETUP_WIZARD_LEAVE_POLICY_STEP]).toBe(
      "Leave Policy"
    );
    expect(SETUP_WIZARD_STEPS[6]).toBe("Work Location");
  });
});
