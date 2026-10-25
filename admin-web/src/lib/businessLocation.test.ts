import assert from "node:assert/strict";
import test from "node:test";
import {
  RSSI_THRESHOLD_EXPLANATION,
  SMALL_GEOFENCE_OWNER_TIP,
  WORKPLACE_WIFI_BROWSER_LIMIT,
  WORKPLACE_WIFI_EMPTY,
  isSmallGeofenceRadius,
  parseMinimumRssiDbm,
  rssiThresholdChoiceFromSaved,
  rssiThresholdValueToSave,
} from "./businessLocation.ts";

test("small-radius warning includes exactly 20 meters", () => {
  assert.equal(isSmallGeofenceRadius(20), true);
  assert.equal(isSmallGeofenceRadius(8), true);
  assert.match(SMALL_GEOFENCE_OWNER_TIP, /under 20 m/);
  assert.doesNotMatch(SMALL_GEOFENCE_OWNER_TIP, /20 m or less/);
  assert.match(SMALL_GEOFENCE_OWNER_TIP, /not a location measurement/);
});

test("warning does not apply above 20 meters", () => {
  assert.equal(isSmallGeofenceRadius(21), false);
  assert.equal(isSmallGeofenceRadius(75), false);
});

test("browser help does not claim it can detect a connected access point", () => {
  assert.match(WORKPLACE_WIFI_BROWSER_LIMIT, /cannot see/i);
  assert.match(WORKPLACE_WIFI_BROWSER_LIMIT, /Android app/);
  assert.doesNotMatch(WORKPLACE_WIFI_BROWSER_LIMIT, /this browser can detect/i);
});

test("RSSI threshold is optional and bounded", () => {
  assert.deepEqual(parseMinimumRssiDbm(""), { ok: true, value: null });
  assert.deepEqual(parseMinimumRssiDbm("  -50 "), { ok: true, value: -50 });
  assert.deepEqual(parseMinimumRssiDbm("-120"), { ok: true, value: -120 });
  assert.deepEqual(parseMinimumRssiDbm("-20"), { ok: true, value: -20 });
  assert.deepEqual(parseMinimumRssiDbm("-19"), { ok: false });
  assert.deepEqual(parseMinimumRssiDbm("-121"), { ok: false });
  assert.deepEqual(parseMinimumRssiDbm("strong"), { ok: false });
});

test("saved RSSI thresholds map to presets, custom values, or off", () => {
  assert.deepEqual(rssiThresholdChoiceFromSaved(null), {
    preset: "off",
    customText: "",
  });
  assert.deepEqual(rssiThresholdChoiceFromSaved(-40), {
    preset: "very-strong",
    customText: "",
  });
  assert.deepEqual(rssiThresholdChoiceFromSaved(-50), {
    preset: "strong",
    customText: "",
  });
  assert.deepEqual(rssiThresholdChoiceFromSaved(-60), {
    preset: "moderate",
    customText: "",
  });
  assert.deepEqual(rssiThresholdChoiceFromSaved(-70), {
    preset: "relaxed",
    customText: "",
  });
  assert.deepEqual(rssiThresholdChoiceFromSaved(-55), {
    preset: "custom",
    customText: "-55",
  });
  assert.match(RSSI_THRESHOLD_EXPLANATION, /registered workplace Wi-Fi/);
  assert.match(RSSI_THRESHOLD_EXPLANATION, /GPS cannot confirm/);
  assert.match(RSSI_THRESHOLD_EXPLANATION, /legitimate employee/);
  assert.match(RSSI_THRESHOLD_EXPLANATION, /exact location/);
});

test("RSSI preset and custom selections save the expected value", () => {
  assert.deepEqual(rssiThresholdValueToSave("off", "-55"), { ok: true, value: null });
  assert.deepEqual(rssiThresholdValueToSave("very-strong", ""), { ok: true, value: -40 });
  assert.deepEqual(rssiThresholdValueToSave("strong", ""), { ok: true, value: -50 });
  assert.deepEqual(rssiThresholdValueToSave("moderate", ""), { ok: true, value: -60 });
  assert.deepEqual(rssiThresholdValueToSave("relaxed", ""), { ok: true, value: -70 });
  assert.deepEqual(rssiThresholdValueToSave("custom", " -55 "), { ok: true, value: -55 });
  assert.deepEqual(rssiThresholdValueToSave("custom", "-120"), { ok: true, value: -120 });
  assert.deepEqual(rssiThresholdValueToSave("custom", "-20"), { ok: true, value: -20 });
  assert.deepEqual(rssiThresholdValueToSave("custom", ""), { ok: false });
  assert.deepEqual(rssiThresholdValueToSave("custom", "-19"), { ok: false });
  assert.deepEqual(rssiThresholdValueToSave("custom", "-121"), { ok: false });
  assert.deepEqual(rssiThresholdValueToSave("custom", "strong"), { ok: false });
});

test("empty Wi-Fi list tells the owner to register from Android", () => {
  assert.match(WORKPLACE_WIFI_EMPTY, /No access points are saved/i);
  assert.match(WORKPLACE_WIFI_EMPTY, /Android app/);
  assert.doesNotMatch(WORKPLACE_WIFI_EMPTY, /this browser can detect/i);
});
