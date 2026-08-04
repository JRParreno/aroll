import L from "leaflet";
import { useEffect, useMemo } from "react";
import {
  Circle,
  MapContainer,
  Marker,
  TileLayer,
  useMap,
  useMapEvents,
} from "react-leaflet";
import {
  DEFAULT_BUSINESS_LATITUDE,
  DEFAULT_BUSINESS_LONGITUDE,
  zoomForRadiusMeters,
} from "@/lib/businessLocation";
import { cn } from "@/lib/utils";
import "leaflet/dist/leaflet.css";

const OSM_TILE_URL = "https://tile.openstreetmap.org/{z}/{x}/{y}.png";
const GEOFENCE_FILL = "#E53935";
const GEOFENCE_STROKE = "#E53935";

const pinIcon = L.divIcon({
  className: "",
  iconSize: [48, 48],
  iconAnchor: [24, 24],
  html: `
    <div style="position:relative;width:48px;height:48px;pointer-events:none;">
      <svg viewBox="0 0 24 24" width="36" height="36"
        style="position:absolute;left:6px;top:0;filter:drop-shadow(0 1px 2px rgba(0,0,0,.35));">
        <path fill="#E53935"
          d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z"/>
      </svg>
      <span style="position:absolute;left:16px;top:16px;width:16px;height:16px;border-radius:9999px;background:#E53935;border:3px solid #fff;box-shadow:0 1px 3px rgba(0,0,0,.4);"></span>
    </div>
  `,
});

type BusinessLocationMapPickerProps = {
  latitude: number | null;
  longitude: number | null;
  geofenceRadiusM: number;
  onPositionChanged: (latitude: number, longitude: number) => void;
  readOnly?: boolean;
  focusToken?: number;
  showMyLocationButton?: boolean;
  onMyLocationPressed?: () => void;
  locating?: boolean;
  className?: string;
};

function MapCamera({
  latitude,
  longitude,
  geofenceRadiusM,
  focusToken,
}: {
  latitude: number | null;
  longitude: number | null;
  geofenceRadiusM: number;
  focusToken: number;
}) {
  const map = useMap();

  useEffect(() => {
    if (latitude == null || longitude == null) {
      map.setView(
        [DEFAULT_BUSINESS_LATITUDE, DEFAULT_BUSINESS_LONGITUDE],
        12
      );
      return;
    }
    const zoom = zoomForRadiusMeters(geofenceRadiusM, latitude);
    map.setView([latitude, longitude], zoom, { animate: true });
  }, [map, latitude, longitude, geofenceRadiusM, focusToken]);

  return null;
}

function MapInteractions({
  readOnly,
  onPositionChanged,
}: {
  readOnly: boolean;
  onPositionChanged: (latitude: number, longitude: number) => void;
}) {
  useMapEvents({
    click(event) {
      if (readOnly) return;
      onPositionChanged(event.latlng.lat, event.latlng.lng);
    },
  });
  return null;
}

export function BusinessLocationMapPicker({
  latitude,
  longitude,
  geofenceRadiusM,
  onPositionChanged,
  readOnly = false,
  focusToken = 0,
  showMyLocationButton = false,
  onMyLocationPressed,
  locating = false,
  className,
}: BusinessLocationMapPickerProps) {
  const hasPin = latitude != null && longitude != null;
  const center = useMemo(
    () =>
      hasPin
        ? ([latitude, longitude] as [number, number])
        : ([DEFAULT_BUSINESS_LATITUDE, DEFAULT_BUSINESS_LONGITUDE] as [
            number,
            number,
          ]),
    [hasPin, latitude, longitude]
  );

  return (
    <div className={cn("relative h-full w-full overflow-hidden bg-[#D6E3EB]", className)}>
      <MapContainer
        center={center}
        className="h-full w-full"
        maxZoom={19}
        minZoom={3}
        scrollWheelZoom
        zoom={hasPin ? zoomForRadiusMeters(geofenceRadiusM, center[0]) : 12}
      >
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
          maxZoom={19}
          url={OSM_TILE_URL}
        />
        <MapCamera
          focusToken={focusToken}
          geofenceRadiusM={geofenceRadiusM}
          latitude={latitude}
          longitude={longitude}
        />
        <MapInteractions
          onPositionChanged={onPositionChanged}
          readOnly={readOnly}
        />
        {hasPin ? (
          <>
            <Circle
              center={center}
              pathOptions={{
                color: GEOFENCE_STROKE,
                fillColor: GEOFENCE_FILL,
                fillOpacity: 0.35,
                weight: 3,
              }}
              radius={geofenceRadiusM}
            />
            <Marker
              draggable={!readOnly}
              eventHandlers={{
                dragend: (event) => {
                  if (readOnly) return;
                  const next = event.target.getLatLng();
                  onPositionChanged(next.lat, next.lng);
                },
              }}
              icon={pinIcon}
              position={center}
            />
          </>
        ) : null}
      </MapContainer>

      {showMyLocationButton ? (
        <button
          className="absolute bottom-3.5 right-3.5 z-[1000] flex h-11 w-11 items-center justify-center rounded-full bg-white shadow-md hover:bg-slate-50 disabled:opacity-60"
          disabled={locating}
          onClick={onMyLocationPressed}
          title="Use my current location"
          type="button"
        >
          {locating ? (
            <span className="h-5 w-5 animate-spin rounded-full border-2 border-slate-400 border-t-transparent" />
          ) : (
            <svg
              className="h-5 w-5 text-slate-700"
              fill="currentColor"
              viewBox="0 0 24 24"
            >
              <path d="M21 3L3 10.53v.98l6.84 2.65L12.49 21h.98L21 3z" />
            </svg>
          )}
        </button>
      ) : null}
    </div>
  );
}
