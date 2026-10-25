/** Mirrors mobile `business_location_defaults.dart`. */
export const DEFAULT_BUSINESS_LATITUDE = 14.5995;
export const DEFAULT_BUSINESS_LONGITUDE = 120.9842;
export const MIN_GEOFENCE_RADIUS_M = 5;
export const MAX_GEOFENCE_RADIUS_M = 200;
export const DEFAULT_GEOFENCE_RADIUS_M = 75;
export const SMALL_GEOFENCE_RADIUS_M = 20;
export const MIN_CONFIGURABLE_RSSI_DBM = -120;
export const MAX_CONFIGURABLE_RSSI_DBM = -20;
export const SUGGESTED_MINIMUM_RSSI_DBM = -50;

export const RSSI_THRESHOLD_PRESETS = [
  { id: "off", label: "Off — saved Wi-Fi address only", dbm: null },
  { id: "very-strong", label: "Very strong (−40 dBm)", dbm: -40 },
  { id: "strong", label: "Strong (−50 dBm)", dbm: -50 },
  { id: "moderate", label: "Moderate (−60 dBm)", dbm: -60 },
  { id: "relaxed", label: "Relaxed (−70 dBm)", dbm: -70 },
  { id: "custom", label: "Custom value", dbm: null },
] as const;

export type RssiThresholdPresetId = (typeof RSSI_THRESHOLD_PRESETS)[number]["id"];

export const RSSI_THRESHOLD_EXPLANATION =
  "The employee must be connected to the registered workplace Wi-Fi. When GPS cannot confirm the work area, the signal must meet the minimum you choose. A stronger requirement can reject a legitimate employee whose phone receives a weaker signal. Signal strength does not prove the employee’s exact location.";

/** Blank clears the floor. Any other value must be a whole number in range. */
export function parseMinimumRssiDbm(
  raw: string
): { ok: true; value: number | null } | { ok: false } {
  const text = raw.trim();
  if (!text) return { ok: true, value: null };
  if (!/^-?\d+$/.test(text)) return { ok: false };
  const value = Number(text);
  if (value < MIN_CONFIGURABLE_RSSI_DBM || value > MAX_CONFIGURABLE_RSSI_DBM) {
    return { ok: false };
  }
  return { ok: true, value };
}

export function rssiThresholdChoiceFromSaved(value: number | null | undefined): {
  preset: RssiThresholdPresetId;
  customText: string;
} {
  if (value == null) return { preset: "off", customText: "" };
  const match = RSSI_THRESHOLD_PRESETS.find(
    (item) => item.id !== "off" && item.id !== "custom" && item.dbm === value
  );
  if (match) return { preset: match.id, customText: "" };
  return { preset: "custom", customText: String(value) };
}

/** Off saves null. A named preset saves its dBm. Custom must be a whole number in range. */
export function rssiThresholdValueToSave(
  preset: RssiThresholdPresetId,
  customText: string
): { ok: true; value: number | null } | { ok: false } {
  if (preset === "off") return { ok: true, value: null };
  const known = RSSI_THRESHOLD_PRESETS.find((item) => item.id === preset);
  if (preset !== "custom" && known?.dbm != null) {
    return { ok: true, value: known.dbm };
  }
  const parsed = parseMinimumRssiDbm(customText);
  if (!parsed.ok || parsed.value == null) return { ok: false };
  return { ok: true, value: parsed.value };
}

export function rssiThresholdStatus(value: number | null | undefined): string {
  if (value == null) return "Signal-strength check: off";
  const choice = rssiThresholdChoiceFromSaved(value);
  if (choice.preset === "custom") {
    return `Signal-strength check: on, custom minimum ${value} dBm`;
  }
  const label = RSSI_THRESHOLD_PRESETS.find((item) => item.id === choice.preset)?.label;
  return `Signal-strength check: on, ${label}`;
}

export const SMALL_GEOFENCE_OWNER_TIP =
  "A small work area is harder for phone GPS, which often drifts by several meters. You can optionally register the workplace Wi-Fi as a backup when the work area is under 20 m. That only confirms the phone is connected to a network you saved. It is not a location measurement and does not replace the map boundary.";

export const WORKPLACE_WIFI_BROWSER_LIMIT =
  "New access points are registered from the Aroll+ Android app while the phone is connected to that network. This browser cannot see the computer’s Wi-Fi address.";

export const WORKPLACE_WIFI_EMPTY =
  "No access points are saved for this worksite yet. Register one in the Aroll+ Android app while the phone is connected to that network.";

export function clampGeofenceRadius(value: number) {
  if (!Number.isFinite(value)) return DEFAULT_GEOFENCE_RADIUS_M;
  return Math.min(
    MAX_GEOFENCE_RADIUS_M,
    Math.max(MIN_GEOFENCE_RADIUS_M, Math.round(value))
  );
}

export function isSmallGeofenceRadius(radiusM: number) {
  return radiusM <= SMALL_GEOFENCE_RADIUS_M;
}

/** Same framing helper as mobile `BusinessLocationMapPicker.zoomForRadiusMeters`. */
export function zoomForRadiusMeters(radiusM: number, latitude: number) {
  const targetPixels = 260;
  const cosLat = Math.min(
    1,
    Math.max(0.25, Math.abs(Math.cos((latitude * Math.PI) / 180)))
  );
  const mpp0 = 156543.03392 * cosLat;
  const paddedDiameter = Math.max(radiusM, 5) * 2.6;
  const zoom = Math.log2((mpp0 * targetPixels) / paddedDiameter);
  return Math.min(18.5, Math.max(16, zoom));
}
