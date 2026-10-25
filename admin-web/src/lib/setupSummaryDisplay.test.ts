/**
 * Run: npx --yes tsx --test src/lib/setupSummaryDisplay.test.ts
 */
import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  buildSetupSummarySections,
  isUnconfiguredSummaryValue,
  ownerPayFrequencyLabel,
  ownerStatusLabel,
  summaryPositionItems,
  summaryShiftItems,
} from "./setupSummaryDisplay.ts";

describe("setup summary display", () => {
  it("uses the same section order as the mobile setup summary", () => {
    const sections = buildSetupSummarySections({
      business: {
        business_name: "North Cafe",
        business_type: "cafe",
        business_code: "MB-D90987",
        application_status: "pending_review",
        address: "12 Main",
      },
      location: {
        address: null,
        latitude: 14.5,
        longitude: 121.0,
        geofence_radius_m: 75,
      },
      shifts: [{ name: "Morning", start_time: "08:00:00", end_time: "17:00:00" }],
      positions: [{ title: "Barista", daily_rate: 500, hourly_rate: 80 }],
      payroll: { pay_period_type: "semi_monthly", next_payday_date: "2026-10-31" },
      attendancePolicy: {
        early_clock_in_minutes: 15,
        on_time_grace_minutes: 5,
        absent_threshold_percent: 50,
        overtime_minimum_minutes: 30,
        maximum_overtime_minutes: 120,
      },
      holidays: [{ id: "1" }, { id: "2" }],
      restDayPolicy: { rest_day_premium_percent: 30 },
    });

    assert.deepEqual(
      sections.map((section) => section.title),
      [
        "Business Profile",
        "Work Location",
        "Work Shifts",
        "Employee Positions",
        "Payroll",
        "Attendance",
        "Holidays",
        "Rest Days",
      ]
    );

    const profile = sections[0].rows;
    assert.equal(profile[0].value, "North Cafe");
    assert.equal(profile[3].value, "Pending Review");
    assert.equal(sections[1].rows[0].value, "12 Main");
    assert.equal(sections[1].rows[1].value, "75m");
    assert.equal(sections[1].rows[2].value, "Enabled");
    assert.equal(sections[2].rows[0].value, "Morning (08:00:00–17:00:00)");
    assert.deepEqual(
      summaryShiftItems([
        { name: "Morning", start_time: "08:00:00", end_time: "17:00:00" },
      ]),
      [{ name: "Morning", detail: "08:00:00–17:00:00" }]
    );
    assert.equal(sections[3].rows[0].value, "Barista — ₱500/day · ₱80/hr");
    assert.deepEqual(
      summaryPositionItems([{ title: "Barista", daily_rate: 500, hourly_rate: 80 }]),
      [{ name: "Barista", detail: "₱500/day · ₱80/hr" }]
    );
    assert.equal(sections[4].rows[0].value, "Twice a month");
    assert.equal(sections[4].rows[1].value, "1 job role configured");
    assert.equal(sections[5].rows[0].value, "Configured");
    assert.equal(sections[5].rows[1].value, "15 min");
    assert.equal(sections[5].rows[3].value, "50%");
    assert.equal(sections[6].rows[0].value, "2 holidays");
    assert.equal(sections[7].rows[0].value, "Extra pay on rest days: 30%");
  });

  it("shows missing and empty setup without treating it as configured", () => {
    const sections = buildSetupSummarySections({
      business: {},
      location: {},
      shifts: [{ name: "  " }],
      positions: [],
      payroll: {},
      attendancePolicy: {},
      holidays: [],
      restDayPolicy: {},
    });

    assert.equal(sections[0].rows[0].value, "Not set");
    assert.equal(ownerStatusLabel(null), "Not set");
    assert.equal(ownerPayFrequencyLabel(null), "Not set");
    assert.equal(sections[1].rows[2].value, "Not set");
    assert.equal(sections[2].rows[0].value, "None configured");
    assert.deepEqual(summaryShiftItems([{ name: "  " }]), []);
    assert.equal(sections[3].rows[0].value, "None configured");
    assert.deepEqual(summaryPositionItems([]), []);
    assert.equal(sections[4].rows[1].value, "No job roles with daily pay yet");
    assert.equal(sections[5].rows[0].value, "Not configured");
    assert.equal(sections[5].rows[3].value, "—%");
    assert.equal(sections[6].rows[0].value, "None configured");
    assert.equal(sections[7].rows[0].value, "Not configured");
    assert.equal(isUnconfiguredSummaryValue("Not set"), true);
    assert.equal(isUnconfiguredSummaryValue("Enabled"), false);
    assert.equal(isUnconfiguredSummaryValue("Configured"), false);
  });
});
