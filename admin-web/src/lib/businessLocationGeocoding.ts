/** Mirrors mobile `business_location_geocoding.dart` (Nominatim reverse). */

import { waitForNominatimSlot } from "./businessPlacesSearch.ts";

const REVERSE_URL = "https://nominatim.openstreetmap.org/reverse";
const reverseCache = new Map<string, string>();

/** Street, barangay, city, and province from a Nominatim address object. */
export function formatNominatimAddress(
  address: Record<string, unknown> | undefined,
  displayName?: string
): string | null {
  if (!address) {
    const display = String(displayName ?? "").trim();
    return display || null;
  }

  const streetParts = [
    String(address.house_number ?? "").trim(),
    String(address.road ?? "").trim(),
  ].filter(Boolean);
  const street = streetParts.join(" ");

  const barangay = [
    address.suburb,
    address.neighbourhood,
    address.village,
    address.quarter,
    address.hamlet,
  ]
    .map((entry) => String(entry ?? "").trim())
    .find((value) => value.length > 0 && value !== "null") ?? "";

  const city = [
    address.city,
    address.municipality,
    address.town,
    address.city_district,
  ]
    .map((entry) => String(entry ?? "").trim())
    .find((value) => value.length > 0 && value !== "null") ?? "";

  const province = [address.state, address.province, address.region]
    .map((entry) => String(entry ?? "").trim())
    .find((value) => value.length > 0 && value !== "null") ?? "";

  const parts = [street, barangay, city, province].filter(Boolean);
  return parts.length ? parts.join(", ") : null;
}

/** Readable address for the UI (barangay / city / province). */
export async function reverseGeocodeAddress(
  latitude: number,
  longitude: number
): Promise<string | null> {
  const cacheKey = `${latitude.toFixed(5)},${longitude.toFixed(5)}`;
  const cached = reverseCache.get(cacheKey);
  if (cached) return cached;
  try {
    await waitForNominatimSlot();
    const params = new URLSearchParams({
      lat: String(latitude),
      lon: String(longitude),
      format: "json",
      addressdetails: "1",
      zoom: "18",
    });
    const response = await fetch(`${REVERSE_URL}?${params}`, {
      headers: { Accept: "application/json" },
    });
    if (!response.ok) return null;
    const data = (await response.json()) as {
      display_name?: string;
      address?: Record<string, unknown>;
    };
    const formatted = formatNominatimAddress(data.address, data.display_name);
    if (!formatted) return null;
    reverseCache.set(cacheKey, formatted);
    return formatted;
  } catch {
    return null;
  }
}
