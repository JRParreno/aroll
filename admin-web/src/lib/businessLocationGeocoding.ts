/** Mirrors mobile `business_location_geocoding.dart` (Nominatim reverse). */

const REVERSE_URL = "https://nominatim.openstreetmap.org/reverse";

let lastReverseAt: number | null = null;

async function throttleReverse() {
  if (lastReverseAt != null) {
    const wait = 1100 - (Date.now() - lastReverseAt);
    if (wait > 0) {
      await new Promise((resolve) => window.setTimeout(resolve, wait));
    }
  }
  lastReverseAt = Date.now();
}

/** Readable address for the UI (barangay / city / province). */
export async function reverseGeocodeAddress(
  latitude: number,
  longitude: number
): Promise<string | null> {
  try {
    await throttleReverse();
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
    const address = data.address;
    if (!address) {
      const display = String(data.display_name ?? "").trim();
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
      .map((e) => String(e ?? "").trim())
      .find((s) => s.length > 0 && s !== "null") ?? "";

    const city = [
      address.city,
      address.municipality,
      address.town,
      address.city_district,
    ]
      .map((e) => String(e ?? "").trim())
      .find((s) => s.length > 0 && s !== "null") ?? "";

    const province = [address.state, address.province, address.region]
      .map((e) => String(e ?? "").trim())
      .find((s) => s.length > 0 && s !== "null") ?? "";

    const parts = [street, barangay, city, province].filter(Boolean);
    return parts.length ? parts.join(", ") : null;
  } catch {
    return null;
  }
}
