/** Free OpenStreetMap Nominatim search — mirrors mobile `business_places_search.dart`. */

export type PlaceSuggestion = {
  description: string;
  placeId?: string;
  latitude: number;
  longitude: number;
};

export type ResolvedPlace = {
  address: string;
  latitude: number;
  longitude: number;
  name?: string;
};

const SEARCH_URL = "https://nominatim.openstreetmap.org/search";
const NOMINATIM_HEADERS = {
  Accept: "application/json",
};

let lastRequestAt: number | null = null;

async function throttleNominatim() {
  if (lastRequestAt != null) {
    const wait = 1100 - (Date.now() - lastRequestAt);
    if (wait > 0) {
      await new Promise((resolve) => window.setTimeout(resolve, wait));
    }
  }
  lastRequestAt = Date.now();
}

function formatNominatimResult(item: Record<string, unknown>): string {
  const display = String(item.display_name ?? "").trim();
  const address = item.address as Record<string, unknown> | undefined;
  if (!address) return display;

  const name = [
    address.amenity,
    address.shop,
    address.building,
    address.tourism,
    address.name,
  ]
    .map((e) => String(e ?? "").trim())
    .find((s) => s.length > 0 && s !== "null") ?? "";

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

  const parts = [name, street, barangay, city, province].filter(Boolean);
  return parts.length ? parts.join(", ") : display;
}

export async function autocompletePlaces(
  input: string
): Promise<PlaceSuggestion[]> {
  const query = input.trim();
  if (query.length < 2) return [];

  try {
    await throttleNominatim();
    const params = new URLSearchParams({
      q: query,
      format: "json",
      addressdetails: "1",
      limit: "6",
      countrycodes: "ph",
    });
    const response = await fetch(`${SEARCH_URL}?${params}`, {
      headers: NOMINATIM_HEADERS,
    });
    if (!response.ok) return [];
    const results = (await response.json()) as Record<string, unknown>[];
    const suggestions: PlaceSuggestion[] = [];
    for (const item of results) {
      const lat = Number.parseFloat(String(item.lat ?? ""));
      const lon = Number.parseFloat(String(item.lon ?? ""));
      const description = formatNominatimResult(item);
      if (!description || !Number.isFinite(lat) || !Number.isFinite(lon)) {
        continue;
      }
      suggestions.push({
        description,
        placeId: String(item.place_id ?? ""),
        latitude: lat,
        longitude: lon,
      });
    }
    return suggestions;
  } catch {
    return [];
  }
}

export async function resolvePlaceSuggestion(
  suggestion: PlaceSuggestion
): Promise<ResolvedPlace | null> {
  return {
    address: suggestion.description,
    latitude: suggestion.latitude,
    longitude: suggestion.longitude,
  };
}

export async function resolveAddress(
  address: string
): Promise<ResolvedPlace | null> {
  const query = address.trim();
  if (query.length < 3) return null;
  const results = await autocompletePlaces(query);
  if (!results.length) return null;
  const first = results[0];
  return {
    address: first.description,
    latitude: first.latitude,
    longitude: first.longitude,
  };
}
