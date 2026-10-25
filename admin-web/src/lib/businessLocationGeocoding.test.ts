/**
 * Nominatim address formatting for the owner workplace pin.
 * Run: node --experimental-strip-types --test src/lib/businessLocationGeocoding.test.ts
 */
import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { formatNominatimAddress } from "./businessLocationGeocoding.ts";

describe("OpenStreetMap address formatting", () => {
  it("builds street, barangay, city, and province", () => {
    assert.equal(
      formatNominatimAddress({
        house_number: "123",
        road: "Mabini Street",
        suburb: "Barangay 1",
        city: "Manila",
        state: "Metro Manila",
      }),
      "123 Mabini Street, Barangay 1, Manila, Metro Manila"
    );
  });

  it("falls back to the display name when no address parts exist", () => {
    assert.equal(
      formatNominatimAddress(undefined, "Manila, Philippines"),
      "Manila, Philippines"
    );
  });

  it("returns null when Nominatim has nothing readable", () => {
    assert.equal(formatNominatimAddress(undefined, "  "), null);
  });
});
