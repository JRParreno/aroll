import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { getBusinessLocation, getMe, updateBusinessLocation } from "@/lib/api";
import { ME_QUERY_KEY } from "@/lib/authSession";

declare global {
  interface Window {
    google?: typeof google;
  }
}

const mapsApiKey = import.meta.env.VITE_GOOGLE_MAPS_API_KEY as string | undefined;

function loadGoogleMaps() {
  if (window.google?.maps) return Promise.resolve();
  if (!mapsApiKey) return Promise.reject(new Error("Missing Google Maps API key"));

  return new Promise<void>((resolve, reject) => {
    const existing = document.querySelector<HTMLScriptElement>(
      "script[data-google-maps]"
    );
    if (existing) {
      existing.addEventListener("load", () => resolve());
      existing.addEventListener("error", reject);
      return;
    }

    const script = document.createElement("script");
    script.dataset.googleMaps = "true";
    script.src = `https://maps.googleapis.com/maps/api/js?key=${mapsApiKey}&libraries=places`;
    script.async = true;
    script.defer = true;
    script.onload = () => resolve();
    script.onerror = reject;
    document.head.appendChild(script);
  });
}

export function OwnerLocationPage() {
  const qc = useQueryClient();
  const mapRef = useRef<HTMLDivElement | null>(null);
  const searchRef = useRef<HTMLInputElement | null>(null);
  const mapInstance = useRef<google.maps.Map | null>(null);
  const markerInstance = useRef<google.maps.Marker | null>(null);
  const circleInstance = useRef<google.maps.Circle | null>(null);
  const [mapsReady, setMapsReady] = useState(false);
  const [mapsError, setMapsError] = useState("");
  const [form, setForm] = useState({
    label: "Main",
    address: "",
    latitude: "",
    longitude: "",
    geofence_radius_m: "75",
  });

  const { data: me } = useQuery({
    queryKey: ME_QUERY_KEY,
    queryFn: getMe,
  });

  const { data: location, isLoading } = useQuery({
    queryKey: ["business-location"],
    queryFn: getBusinessLocation,
  });

  const businessName =
    me?.business_name ?? localStorage.getItem("aroll_business_name") ?? "Aroll+";

  useEffect(() => {
    if (!location) return;
    setForm({
      label: location.label,
      address: location.address,
      latitude: location.latitude?.toString() ?? "",
      longitude: location.longitude?.toString() ?? "",
      geofence_radius_m: String(location.geofence_radius_m),
    });
  }, [location]);

  useEffect(() => {
    loadGoogleMaps()
      .then(() => setMapsReady(true))
      .catch(() =>
        setMapsError(
          "Google Maps API key is required for map search and interactive geofencing."
        )
      );
  }, []);

  useEffect(() => {
    if (!mapsReady || !mapRef.current || !window.google?.maps) return;

    const lat = Number(form.latitude) || 14.5995;
    const lng = Number(form.longitude) || 120.9842;
    const center = { lat, lng };

    if (!mapInstance.current) {
      mapInstance.current = new window.google.maps.Map(mapRef.current, {
        center,
        zoom: 16,
        mapTypeControl: false,
        streetViewControl: false,
      });
      markerInstance.current = new window.google.maps.Marker({
        map: mapInstance.current,
        position: center,
        draggable: true,
      });
      circleInstance.current = new window.google.maps.Circle({
        map: mapInstance.current,
        center,
        radius: Number(form.geofence_radius_m),
        fillColor: "#b9d8ee",
        fillOpacity: 0.25,
        strokeColor: "#1f456b",
        strokeWeight: 2,
      });
      markerInstance.current.addListener("dragend", () => {
        const position = markerInstance.current?.getPosition();
        if (!position) return;
        setForm((current) => ({
          ...current,
          latitude: String(position.lat()),
          longitude: String(position.lng()),
        }));
      });
      mapInstance.current.addListener("click", (event: google.maps.MapMouseEvent) => {
        if (!event.latLng) return;
        setForm((current) => ({
          ...current,
          latitude: String(event.latLng!.lat()),
          longitude: String(event.latLng!.lng()),
        }));
      });
    }

    mapInstance.current.setCenter(center);
    markerInstance.current?.setPosition(center);
    circleInstance.current?.setCenter(center);
    circleInstance.current?.setRadius(Number(form.geofence_radius_m));
  }, [mapsReady, form.latitude, form.longitude, form.geofence_radius_m]);

  useEffect(() => {
    if (!mapsReady || !searchRef.current || !window.google?.maps?.places) return;
    const autocomplete = new window.google.maps.places.Autocomplete(
      searchRef.current,
      {
        fields: ["formatted_address", "geometry", "name"],
      }
    );
    autocomplete.addListener("place_changed", () => {
      const place = autocomplete.getPlace();
      const location = place.geometry?.location;
      if (!location) return;
      setForm((current) => ({
        ...current,
        label: place.name || current.label,
        address: place.formatted_address || current.address,
        latitude: String(location.lat()),
        longitude: String(location.lng()),
      }));
    });
    return () => {
      window.google?.maps.event.clearInstanceListeners(autocomplete);
    };
  }, [mapsReady]);

  const save = useMutation({
    mutationFn: () =>
      updateBusinessLocation({
        label: form.label,
        address: form.address,
        latitude: Number(form.latitude),
        longitude: Number(form.longitude),
        geofence_radius_m: Number(form.geofence_radius_m),
      }),
    onSuccess: () => {
      toast.success("Business location saved");
      qc.invalidateQueries({ queryKey: ["business-location"] });
      qc.invalidateQueries({ queryKey: ["setup-status"] });
    },
    onError: () => toast.error("Failed to save location"),
  });

  const radius = Number(form.geofence_radius_m);
  const canSave =
    form.address.trim().length >= 5 &&
    form.latitude !== "" &&
    form.longitude !== "" &&
    radius >= 20 &&
    radius <= 200;

  return (
    <div className="min-h-screen bg-[#F7F8FA]">
      <header className="flex h-[74px] items-center justify-between border-b border-slate-200 bg-white px-5 sm:px-8">
        <h1 className="text-2xl font-semibold text-[#1F2937]">
          Location
        </h1>
        <div className="flex h-12 w-12 items-center justify-center overflow-hidden rounded-full bg-[#f7ead4] p-1 shadow-sm">
          <div className="flex h-full w-full items-center justify-center rounded-full bg-[#354151] text-sm font-bold text-white">
            {businessName.slice(0, 1).toUpperCase()}
          </div>
        </div>
      </header>

      <main className="px-5 py-6 sm:px-8">
        <div className="h-[260px] overflow-hidden rounded-2xl border border-slate-200 bg-[#d6e3eb] shadow-sm">
          {mapsReady ? (
            <div className="h-full w-full" ref={mapRef} />
          ) : (
            <div className="flex h-full items-center justify-center px-6 text-center text-sm font-semibold text-[#1f456b]">
              {mapsError || "Loading Google Maps..."}
            </div>
          )}
        </div>

        <div className="mx-auto mt-6 max-w-2xl space-y-7 rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
          <Input
            ref={searchRef}
            className="h-12 bg-white px-4 font-medium"
            placeholder="Address"
            value={form.address}
            onChange={(event) =>
              setForm({ ...form, address: event.target.value })
            }
            disabled={isLoading}
          />

          <div className="grid gap-4 sm:grid-cols-2">
            <Input
              type="number"
              step="any"
              value={form.latitude}
              onChange={(event) =>
                setForm({ ...form, latitude: event.target.value })
              }
              placeholder="Latitude"
            />
            <Input
              type="number"
              step="any"
              value={form.longitude}
              onChange={(event) =>
                setForm({ ...form, longitude: event.target.value })
              }
              placeholder="Longitude"
            />
          </div>

          <div>
            <div className="mb-2 flex items-center justify-between">
              <span className="text-sm font-semibold text-[#1F2937]">
                Adjustable Radius Slider
              </span>
              <Input
                className="h-7 w-20 bg-white text-center text-xs"
                type="number"
                min={20}
                max={200}
                value={form.geofence_radius_m}
                onChange={(event) =>
                  setForm({ ...form, geofence_radius_m: event.target.value })
                }
              />
            </div>
            <input
              className="w-full accent-[#1f456b]"
              type="range"
              min={20}
              max={200}
              step={5}
              value={form.geofence_radius_m}
              onChange={(event) =>
                setForm({ ...form, geofence_radius_m: event.target.value })
              }
            />
            <div className="flex justify-between text-[10px] font-medium text-black">
              <span>20m - 200m</span>
              <span>{form.geofence_radius_m}m</span>
            </div>
          </div>

          <div className="flex justify-center gap-4 pt-4">
            <Button
              className="min-w-32 rounded-full bg-[#b9d8ee] text-white hover:bg-[#a9cce6]"
              type="button"
              variant="secondary"
              onClick={() => {
                if (!location) return;
                setForm({
                  label: location.label,
                  address: location.address,
                  latitude: location.latitude?.toString() ?? "",
                  longitude: location.longitude?.toString() ?? "",
                  geofence_radius_m: String(location.geofence_radius_m),
                });
              }}
            >
              Cancel
            </Button>
            <Button
              className="min-w-36 rounded-full bg-[#1f456b] text-white hover:bg-[#17395d]"
              disabled={!canSave || save.isPending}
              onClick={() => save.mutate()}
            >
              Save Location
            </Button>
          </div>
        </div>
      </main>
    </div>
  );
}
