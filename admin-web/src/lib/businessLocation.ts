/** Mirrors mobile `business_location_defaults.dart`. */
export const DEFAULT_BUSINESS_LATITUDE = 14.5995;
export const DEFAULT_BUSINESS_LONGITUDE = 120.9842;
export const MIN_GEOFENCE_RADIUS_M = 5;
export const MAX_GEOFENCE_RADIUS_M = 200;
export const DEFAULT_GEOFENCE_RADIUS_M = 75;
export const SMALL_GEOFENCE_RADIUS_M = 20;

export const SMALL_GEOFENCE_OWNER_TIP =
  "Warning: radii under 20 m can be unreliable because phone GPS often drifts 8–15 m. Prefer outdoor placement near the pin. You can still use a small radius if needed; 25–50 m is more reliable.";

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
