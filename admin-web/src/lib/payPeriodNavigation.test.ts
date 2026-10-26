/**
 * Run: node --test src/lib/payPeriodNavigation.test.ts
 */
import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  canOpenNextPayPeriod,
  nextPeriodAsOf,
  previousPeriodAsOf,
  shiftIsoDate,
} from "./payPeriodNavigation.ts";

describe("pay period navigation dates", () => {
  it("steps to the day before the period starts", () => {
    assert.equal(previousPeriodAsOf("2026-07-16"), "2026-07-15");
  });

  it("steps to the day after the period ends", () => {
    assert.equal(nextPeriodAsOf("2026-07-15"), "2026-07-16");
  });

  it("crosses month and year boundaries", () => {
    assert.equal(previousPeriodAsOf("2026-01-01"), "2025-12-31");
    assert.equal(nextPeriodAsOf("2026-12-31"), "2027-01-01");
    assert.equal(shiftIsoDate("2024-02-28", 1), "2024-02-29");
  });

  it("opens Next only after the selected period has ended", () => {
    assert.equal(canOpenNextPayPeriod("completed"), true);
    assert.equal(canOpenNextPayPeriod("current"), false);
    assert.equal(canOpenNextPayPeriod("upcoming"), false);
    assert.equal(canOpenNextPayPeriod(null), false);
    assert.equal(canOpenNextPayPeriod(undefined), false);
  });
});
