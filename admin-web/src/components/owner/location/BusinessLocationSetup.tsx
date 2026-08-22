import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { LocateFixed, MapPin, Search, X } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { BusinessLocationMapPicker } from "@/components/owner/location/BusinessLocationMapPicker";
import { getBusinessLocation, getMe, updateBusinessLocation } from "@/lib/api";
import { ME_QUERY_KEY } from "@/lib/authSession";
import {
  DEFAULT_GEOFENCE_RADIUS_M,
  MAX_GEOFENCE_RADIUS_M,
  MIN_GEOFENCE_RADIUS_M,
  SMALL_GEOFENCE_OWNER_TIP,
  clampGeofenceRadius,
  isSmallGeofenceRadius,
} from "@/lib/businessLocation";
import { reverseGeocodeAddress } from "@/lib/businessLocationGeocoding";
import {
  autocompletePlaces,
  resolveAddress,
  resolvePlaceSuggestion,
  type PlaceSuggestion,
} from "@/lib/businessPlacesSearch";
import { cn } from "@/lib/utils";

type LocationForm = {
  label: string;
  address: string;
  latitude: number | null;
  longitude: number | null;
  geofence_radius_m: number;
};

type BusinessLocationSetupProps = {
  description?: string;
  saveLabel?: string;
  mapHeightClassName?: string;
  className?: string;
  onSaved?: () => void;
};

export function BusinessLocationSetup({
  description = "Set your workplace on the map and choose how close employees must be before they can time in or time out.",
  saveLabel = "Save Location",
  mapHeightClassName = "h-[320px] sm:h-[420px]",
  className,
  onSaved,
}: BusinessLocationSetupProps) {
  const qc = useQueryClient();
  const addressEditedManually = useRef(false);
  const searchDebounce = useRef<number | null>(null);
  const reverseDebounce = useRef<number | null>(null);

  const [form, setForm] = useState<LocationForm>({
    label: "Main",
    address: "",
    latitude: null,
    longitude: null,
    geofence_radius_m: DEFAULT_GEOFENCE_RADIUS_M,
  });
  const [snapshot, setSnapshot] = useState<LocationForm | null>(null);
  const [locating, setLocating] = useState(false);
  const [searching, setSearching] = useState(false);
  const [suggestions, setSuggestions] = useState<PlaceSuggestion[]>([]);
  const [mapFocusToken, setMapFocusToken] = useState(0);

  const { data: me } = useQuery({
    queryKey: ME_QUERY_KEY,
    queryFn: getMe,
  });
  const isManager = me?.role === "manager";

  const { data: location, isLoading, isError, refetch } = useQuery({
    queryKey: ["business-location"],
    queryFn: getBusinessLocation,
  });

  useEffect(() => {
    if (!location) return;
    const next: LocationForm = {
      label: location.label || "Main",
      address: location.address || "",
      latitude: location.latitude,
      longitude: location.longitude,
      geofence_radius_m: clampGeofenceRadius(location.geofence_radius_m),
    };
    setForm(next);
    setSnapshot(next);
    addressEditedManually.current = false;
    setSuggestions([]);
  }, [location]);

  useEffect(() => {
    return () => {
      if (searchDebounce.current) window.clearTimeout(searchDebounce.current);
      if (reverseDebounce.current) window.clearTimeout(reverseDebounce.current);
    };
  }, []);

  const bumpMapFocus = () => setMapFocusToken((token) => token + 1);

  const applyReverseGeocode = async (lat: number, lng: number) => {
    if (addressEditedManually.current) return;
    const address = await reverseGeocodeAddress(lat, lng);
    if (!address?.trim()) return;
    setForm((current) => ({ ...current, address }));
  };

  const scheduleReverseGeocode = (lat: number, lng: number) => {
    if (reverseDebounce.current) window.clearTimeout(reverseDebounce.current);
    reverseDebounce.current = window.setTimeout(() => {
      void applyReverseGeocode(lat, lng);
    }, 450);
  };

  const applyCoordinates = (
    lat: number,
    lng: number,
    options?: { reverseGeocode?: boolean; focus?: boolean }
  ) => {
    setForm((current) => ({
      ...current,
      latitude: lat,
      longitude: lng,
    }));
    setSuggestions([]);
    if (options?.focus) bumpMapFocus();
    if (options?.reverseGeocode !== false) {
      addressEditedManually.current = false;
      scheduleReverseGeocode(lat, lng);
    }
  };

  const useCurrentLocation = () => {
    if (isManager) return;
    if (!navigator.geolocation) {
      toast.error("Location is not supported in this browser.");
      return;
    }
    setLocating(true);
    navigator.geolocation.getCurrentPosition(
      (position) => {
        setLocating(false);
        applyCoordinates(position.coords.latitude, position.coords.longitude, {
          reverseGeocode: true,
          focus: true,
        });
        toast.success("Moved pin to your current location.");
      },
      () => {
        setLocating(false);
        toast.error(
          "Could not get your current location. Check browser permissions and try again."
        );
      },
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 }
    );
  };

  const fetchSuggestions = async (query: string) => {
    if (isManager) return;
    const trimmed = query.trim();
    if (trimmed.length < 2) {
      setSuggestions([]);
      return;
    }
    setSearching(true);
    try {
      const results = await autocompletePlaces(trimmed);
      setSuggestions(results);
    } catch {
      setSuggestions([]);
    } finally {
      setSearching(false);
    }
  };

  const onAddressChanged = (value: string) => {
    addressEditedManually.current = true;
    setForm((current) => ({ ...current, address: value }));
    if (searchDebounce.current) window.clearTimeout(searchDebounce.current);
    searchDebounce.current = window.setTimeout(() => {
      void fetchSuggestions(value);
    }, 350);
  };

  const selectSuggestion = async (suggestion: PlaceSuggestion) => {
    setSearching(true);
    setSuggestions([]);
    try {
      const place = await resolvePlaceSuggestion(suggestion);
      if (!place) {
        toast.error("Could not find that address.");
        return;
      }
      addressEditedManually.current = true;
      setForm((current) => ({
        ...current,
        address: place.address,
        latitude: place.latitude,
        longitude: place.longitude,
        label: place.name?.trim() || current.label || "Main",
      }));
      bumpMapFocus();
    } catch {
      toast.error("Could not find that address.");
    } finally {
      setSearching(false);
    }
  };

  const submitAddressSearch = async () => {
    const query = form.address.trim();
    if (query.length < 3 || isManager) return;
    setSearching(true);
    setSuggestions([]);
    try {
      const place = await resolveAddress(query);
      if (!place) {
        toast.error("No results for that address.");
        return;
      }
      addressEditedManually.current = true;
      setForm((current) => ({
        ...current,
        address: place.address,
        latitude: place.latitude,
        longitude: place.longitude,
      }));
      bumpMapFocus();
    } catch {
      toast.error("No results for that address.");
    } finally {
      setSearching(false);
    }
  };

  const save = useMutation({
    mutationFn: () => {
      if (
        form.latitude == null ||
        form.longitude == null ||
        form.address.trim().length < 5
      ) {
        return Promise.reject(new Error("Incomplete location"));
      }
      return updateBusinessLocation({
        label: form.label.trim() || "Main",
        address: form.address.trim(),
        latitude: form.latitude,
        longitude: form.longitude,
        geofence_radius_m: clampGeofenceRadius(form.geofence_radius_m),
      });
    },
    onSuccess: () => {
      toast.success("Business location saved");
      setSnapshot(form);
      addressEditedManually.current = false;
      void qc.invalidateQueries({ queryKey: ["business-location"] });
      void qc.invalidateQueries({ queryKey: ["setup-status"] });
      onSaved?.();
    },
    onError: () => toast.error("Failed to save location"),
  });

  const canSave =
    !isManager &&
    !save.isPending &&
    form.address.trim().length >= 5 &&
    form.latitude != null &&
    form.longitude != null &&
    form.geofence_radius_m >= MIN_GEOFENCE_RADIUS_M &&
    form.geofence_radius_m <= MAX_GEOFENCE_RADIUS_M;

  const cancelEdits = () => {
    if (!snapshot) return;
    addressEditedManually.current = false;
    setSuggestions([]);
    setForm(snapshot);
    bumpMapFocus();
  };

  if (isError) {
    return (
      <div className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800">
        Could not load business location.{" "}
        <button className="font-semibold underline" onClick={() => void refetch()} type="button">
          Retry
        </button>
      </div>
    );
  }

  return (
    <div className={cn("space-y-5", className)}>
      {isManager ? (
        <div className="rounded-xl border border-blue-200 bg-blue-50 px-4 py-3 text-sm text-slate-800">
          Only the business owner can update the business location.
        </div>
      ) : null}

      <p className="text-sm text-[#6B7280]">{description}</p>

      <div
        className={cn(
          "overflow-hidden rounded-2xl border border-slate-200 shadow-sm",
          mapHeightClassName
        )}
      >
        <BusinessLocationMapPicker
          focusToken={mapFocusToken}
          geofenceRadiusM={form.geofence_radius_m}
          latitude={form.latitude}
          locating={locating}
          longitude={form.longitude}
          onMyLocationPressed={useCurrentLocation}
          onPositionChanged={(lat, lng) =>
            applyCoordinates(lat, lng, { reverseGeocode: true })
          }
          readOnly={isManager}
          showMyLocationButton={!isManager}
        />
      </div>

      <div className="space-y-5 rounded-2xl border border-slate-200 bg-white p-5 shadow-sm sm:p-6">
        <div>
          <h2 className="text-base font-semibold text-[#111827]">
            Add Business Address
          </h2>
        </div>

        <div className="space-y-2">
          <div className="relative">
            <Search className="pointer-events-none absolute left-3 top-3.5 h-4 w-4 text-[#6B7280]" />
            <Input
              className="h-11 rounded-xl bg-white pl-10 pr-10 shadow-sm"
              disabled={isLoading || isManager}
              onChange={(event) => onAddressChanged(event.target.value)}
              onKeyDown={(event) => {
                if (event.key === "Enter") {
                  event.preventDefault();
                  void submitAddressSearch();
                }
              }}
              placeholder="Search street, barangay, or place"
              value={form.address}
            />
            {searching ? (
              <span className="absolute right-3 top-3.5 h-4 w-4 animate-spin rounded-full border-2 border-slate-400 border-t-transparent" />
            ) : form.address ? (
              <button
                className="absolute right-2 top-2.5 rounded-md p-1 text-[#6B7280] hover:bg-slate-100"
                onClick={() => {
                  addressEditedManually.current = true;
                  setForm((current) => ({ ...current, address: "" }));
                  setSuggestions([]);
                }}
                type="button"
              >
                <X className="h-4 w-4" />
              </button>
            ) : null}
          </div>

          {suggestions.length > 0 ? (
            <ul className="max-h-36 overflow-auto rounded-xl border border-slate-200 bg-white shadow-sm">
              {suggestions.slice(0, 6).map((suggestion) => (
                <li key={`${suggestion.placeId}-${suggestion.description}`}>
                  <button
                    className="flex w-full items-start gap-2 px-3 py-2.5 text-left text-sm text-[#111827] hover:bg-slate-50"
                    onClick={() => void selectSuggestion(suggestion)}
                    type="button"
                  >
                    <MapPin className="mt-0.5 h-4 w-4 shrink-0 text-[#6B7280]" />
                    <span className="line-clamp-2">{suggestion.description}</span>
                  </button>
                </li>
              ))}
            </ul>
          ) : null}

          {!isManager ? (
            <button
              className="inline-flex items-center gap-2 text-sm font-semibold text-[#1F456B] hover:underline disabled:opacity-60"
              disabled={locating}
              onClick={useCurrentLocation}
              type="button"
            >
              <LocateFixed className="h-4 w-4" />
              {locating ? "Getting your location…" : "Use My Current Location"}
            </button>
          ) : null}
        </div>

        <div>
          <div className="mb-2 flex items-center justify-between gap-3">
            <h3 className="text-base font-semibold text-[#111827]">
              Set Attendance Distance
            </h3>
            <span className="rounded-lg border border-slate-200 bg-[#F3F4F6] px-2.5 py-1 text-xs font-bold text-[#111827]">
              {form.geofence_radius_m}m
            </span>
          </div>
          <input
            className="w-full accent-[#1F456B] disabled:opacity-50"
            disabled={isManager}
            max={MAX_GEOFENCE_RADIUS_M}
            min={MIN_GEOFENCE_RADIUS_M}
            onChange={(event) =>
              setForm((current) => ({
                ...current,
                geofence_radius_m: clampGeofenceRadius(Number(event.target.value)),
              }))
            }
            step={1}
            type="range"
            value={form.geofence_radius_m}
          />
          <div className="mt-1 flex justify-between text-xs font-semibold text-[#374151]">
            <span>
              {MIN_GEOFENCE_RADIUS_M}m - {MAX_GEOFENCE_RADIUS_M}m
            </span>
            <span>{form.geofence_radius_m}m</span>
          </div>
          {isSmallGeofenceRadius(form.geofence_radius_m) ? (
            <div className="mt-3 rounded-xl border border-amber-200 bg-amber-50 px-3 py-2.5 text-xs leading-5 text-amber-900">
              {SMALL_GEOFENCE_OWNER_TIP}
            </div>
          ) : null}
        </div>

        <div className="flex flex-col-reverse gap-3 pt-1 sm:flex-row">
          <Button
            className="h-12 flex-1 rounded-xl bg-[#B9D8EE] text-white hover:bg-[#A9CCE6]"
            disabled={isManager || !snapshot}
            onClick={cancelEdits}
            type="button"
            variant="outline"
          >
            Cancel
          </Button>
          <Button
            className="h-12 flex-1 rounded-xl bg-[#1F456B] text-white hover:bg-[#17395D]"
            disabled={!canSave}
            onClick={() => save.mutate()}
            type="button"
          >
            {save.isPending ? "Saving…" : saveLabel}
          </Button>
        </div>
      </div>
    </div>
  );
}
