/**
 * UI presentation tests for Holiday Management copy helpers.
 * Run: npx --yes tsx --test src/lib/holidayManagementCopy.test.ts
 */
import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  HOLIDAY_TERMS,
  buildRuleSummary,
  compactRuleLine,
  holidayOtCardLine,
  holidayOtPremiumOwnerLabel,
  holidayPayRateCardLine,
  holidayPayRateLabel,
  holidayPayRateParts,
  multiplierToPercentInput,
  otPremiumNote,
  percentToPayMultiplier,
  unworkedRulePresentation,
  workedRateNote,
} from "./holidayManagementCopy.ts";

describe("holiday pay rate labels", () => {
  it("1.0 displays as Regular Pay — 100%", () => {
    assert.equal(holidayPayRateLabel(1.0), "Regular Pay — 100%");
  });
  it("1.3 displays as 130% Pay", () => {
    assert.equal(holidayPayRateLabel(1.3), "130% Pay");
  });
  it("1.5 displays as 150% Pay", () => {
    assert.equal(holidayPayRateLabel(1.5), "150% Pay");
  });
  it("2.0 displays as Double Pay — 200%", () => {
    assert.equal(holidayPayRateLabel(2.0), "Double Pay — 200%");
  });
  it("3.0 displays as Triple Pay — 300%", () => {
    assert.equal(holidayPayRateLabel(3.0), "Triple Pay — 300%");
  });
  it("custom multiplier displays percent without rewriting storage", () => {
    assert.equal(holidayPayRateLabel(1.75), "175% Pay");
  });
});

describe("custom percent → pay_multiplier", () => {
  it("200% maps to 2.0", () => {
    assert.equal(percentToPayMultiplier(200), 2.0);
  });
  it("130% maps to 1.3", () => {
    assert.equal(percentToPayMultiplier(130), 1.3);
  });
  it("existing custom multiplier round-trips", () => {
    const stored = 1.75;
    const pct = Number(multiplierToPercentInput(stored));
    assert.equal(percentToPayMultiplier(pct), stored);
  });
});

describe("OT premium presentation", () => {
  it("null OT premium displays as 0%", () => {
    assert.equal(
      holidayOtPremiumOwnerLabel(null),
      "No additional holiday OT premium — 0%"
    );
  });
  it("30 OT premium label", () => {
    assert.equal(holidayOtPremiumOwnerLabel(30), "30% additional — 30%");
  });
});

describe("is_paid / unworked presentation preserved", () => {
  it("locks PH regular and special", () => {
    const regular = unworkedRulePresentation("philippine_labor", "regular", false);
    assert.equal(regular.editable, false);
    assert.equal(regular.effectivePaysUnworked, true);
    const special = unworkedRulePresentation(
      "philippine_labor",
      "special_non_working",
      true
    );
    assert.equal(special.editable, false);
    assert.equal(special.effectivePaysUnworked, false);
  });
  it("company keeps is_paid toggle semantics", () => {
    const on = unworkedRulePresentation("philippine_labor", "company", true);
    assert.equal(on.editable, true);
    assert.equal(on.effectivePaysUnworked, true);
  });
});

describe("short holiday pay copy", () => {
  it("uses the approved worked, unworked, and OT lines", () => {
    assert.equal(
      workedRateNote(1, false),
      "Regular pay. No extra holiday pay."
    );
    assert.equal(
      workedRateNote(2, false),
      "Double pay for eligible holiday work."
    );
    assert.match(workedRateNote(1.75, true), /200% is double pay/);
    assert.equal(
      unworkedRulePresentation("philippine_labor", "regular", false).explanation,
      "Regular holidays are paid even when the employee does not work."
    );
    assert.equal(
      unworkedRulePresentation("philippine_labor", "special_non_working", true)
        .explanation,
      "Special non-working days are not paid when the employee does not work."
    );
    assert.equal(
      unworkedRulePresentation("philippine_labor", "company", true).explanation,
      "Pay their scheduled day if they do not work."
    );
    assert.equal(
      otPremiumNote(""),
      "Extra pay for approved overtime worked this holiday."
    );
    assert.equal(
      otPremiumNote("30"),
      "Extra pay for approved overtime worked this holiday."
    );
    assert.equal(holidayPayRateParts(2).title, "Double Pay");
    assert.equal(holidayPayRateParts(2).detail, "200%");
    assert.equal(holidayPayRateParts(1).title, "Regular Pay");
    assert.equal(holidayPayRateCardLine(2), "Double Pay · 200%");
    assert.equal(holidayOtCardLine(null), "No Extra OT");
    assert.equal(holidayOtCardLine(30), "30%");
  });
});

describe("list / summary load existing holidays", () => {
  it("compact line uses human-readable rate", () => {
    assert.equal(
      compactRuleLine({
        mode: "philippine_labor",
        holidayType: "company",
        isPaid: true,
        payMultiplier: 2.0,
      }),
      "Double Pay — 200% · Pay Scheduled Day"
    );
  });
  it("summary uses total pay-rate language and existing API field meaning", () => {
    const summary = buildRuleSummary({
      name: "Independence Day",
      holidayType: "regular",
      mode: "philippine_labor",
      isPaid: true,
      payMultiplier: 2.0,
      otPremiumRaw: "",
    });
    assert.match(summary.worked[0], /Double Pay — 200%/);
    assert.match(summary.worked[0], /total pay rate/);
    assert.equal(HOLIDAY_TERMS.workedPremium, "Holiday Pay Rate");
    assert.equal(HOLIDAY_TERMS.editHolidayPay, "Edit holiday pay");
  });
});
