import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import {
  deleteWorkplaceWifi,
  getWorkplaceWifiRssi,
  listWorkplaceWifi,
  updateWorkplaceWifi,
  updateWorkplaceWifiRssi,
} from "@/lib/api";
import {
  RSSI_THRESHOLD_EXPLANATION,
  RSSI_THRESHOLD_PRESETS,
  rssiThresholdChoiceFromSaved,
  rssiThresholdStatus,
  rssiThresholdValueToSave,
  type RssiThresholdPresetId,
  SMALL_GEOFENCE_RADIUS_M,
  WORKPLACE_WIFI_BROWSER_LIMIT,
  WORKPLACE_WIFI_EMPTY,
} from "@/lib/businessLocation";

const WIFI_QUERY_KEY = ["workplace-wifi"] as const;
const RSSI_QUERY_KEY = ["workplace-wifi-rssi"] as const;

export function WorkplaceWifiPanel({
  radiusM,
  canManage,
}: {
  radiusM: number;
  canManage: boolean;
}) {
  const queryClient = useQueryClient();
  const [rssiPreset, setRssiPreset] = useState<RssiThresholdPresetId>("off");
  const [rssiText, setRssiText] = useState("");
  const rssi = useQuery({
    queryKey: RSSI_QUERY_KEY,
    queryFn: getWorkplaceWifiRssi,
    enabled: canManage,
  });
  useEffect(() => {
    if (!rssi.data) return;
    const choice = rssiThresholdChoiceFromSaved(rssi.data.minimum_rssi_dbm);
    setRssiPreset(choice.preset);
    setRssiText(choice.customText);
  }, [rssi.data]);
  const points = useQuery({
    queryKey: WIFI_QUERY_KEY,
    queryFn: listWorkplaceWifi,
    enabled: canManage,
  });

  const refresh = () => queryClient.invalidateQueries({ queryKey: WIFI_QUERY_KEY });

  const toggle = useMutation({
    mutationFn: ({ id, enabled }: { id: string; enabled: boolean }) =>
      updateWorkplaceWifi(id, { enabled }),
    onSuccess: async (_data, variables) => {
      await refresh();
      toast.success(
        variables.enabled ? "Workplace Wi-Fi enabled." : "Workplace Wi-Fi disabled."
      );
    },
    onError: () => toast.error("Workplace Wi-Fi could not be updated."),
  });

  const saveRssi = useMutation({
    mutationFn: updateWorkplaceWifiRssi,
    onSuccess: async (saved) => {
      await queryClient.invalidateQueries({ queryKey: RSSI_QUERY_KEY });
      toast.success(
        saved.minimum_rssi_dbm == null
          ? "Signal-strength check is off."
          : `${rssiThresholdStatus(saved.minimum_rssi_dbm)}.`
      );
    },
    onError: () => toast.error("The signal-strength check could not be saved."),
  });

  const remove = useMutation({
    mutationFn: deleteWorkplaceWifi,
    onSuccess: async () => {
      await refresh();
      toast.success("Workplace Wi-Fi removed.");
    },
    onError: () => toast.error("Workplace Wi-Fi could not be removed."),
  });

  if (!canManage) return null;

  const rows = points.data ?? [];
  return (
    <section className="rounded-2xl border border-slate-200 bg-slate-50 p-4">
      <h3 className="text-sm font-semibold text-slate-900">Workplace Wi-Fi</h3>
      <p className="mt-1 text-xs leading-5 text-slate-600">
        {WORKPLACE_WIFI_BROWSER_LIMIT}
      </p>
      <div className="mt-3 rounded-xl border border-slate-200 bg-white px-3 py-2">
        <p className="text-xs font-medium text-slate-800">
          {rssiThresholdStatus(rssi.data?.minimum_rssi_dbm)}
        </p>
        <p className="mt-1 text-xs leading-5 text-slate-500">{RSSI_THRESHOLD_EXPLANATION}</p>
        <label className="mt-2 block text-xs text-slate-600" htmlFor="rssi-threshold-preset">
          Signal requirement
        </label>
        <select
          id="rssi-threshold-preset"
          className="mt-1 h-9 w-full rounded-lg border border-slate-200 bg-white px-2 text-sm"
          value={rssiPreset}
          onChange={(event) => {
            const next = event.target.value as RssiThresholdPresetId;
            if (next === "custom" && rssiPreset !== "custom" && rssiText.trim() === "") {
              const current = RSSI_THRESHOLD_PRESETS.find((item) => item.id === rssiPreset);
              if (current?.dbm != null) setRssiText(String(current.dbm));
            }
            setRssiPreset(next);
          }}
        >
          {RSSI_THRESHOLD_PRESETS.map((option) => (
            <option key={option.id} value={option.id}>
              {option.label}
            </option>
          ))}
        </select>
        {rssiPreset === "custom" ? (
          <>
            <label className="mt-2 block text-xs text-slate-600" htmlFor="minimum-rssi-dbm">
              Custom minimum (dBm)
            </label>
            <input
              id="minimum-rssi-dbm"
              className="mt-1 h-9 w-full rounded-lg border border-slate-200 px-2 text-sm"
              inputMode="numeric"
              placeholder="-55"
              value={rssiText}
              onChange={(event) => setRssiText(event.target.value)}
            />
            <p className="mt-1 text-xs leading-5 text-slate-500">
              Enter a whole number from −120 to −20. A number closer to zero requires a
              stronger signal.
            </p>
          </>
        ) : null}
        <Button
          type="button"
          variant="outline"
          className="mt-2 h-8 rounded-lg px-3 text-xs"
          disabled={saveRssi.isPending}
          onClick={() => {
            const parsed = rssiThresholdValueToSave(rssiPreset, rssiText);
            if (!parsed.ok) {
              toast.error("Enter a whole number from -120 to -20 dBm.");
              return;
            }
            saveRssi.mutate(parsed.value);
          }}
        >
          Save signal check
        </Button>
      </div>
      {radiusM >= SMALL_GEOFENCE_RADIUS_M ? (
        <p className="mt-2 text-xs leading-5 text-slate-600">
          Saved networks are checked only when the work area is under 20 m.
        </p>
      ) : (
        <p className="mt-2 text-xs leading-5 text-slate-600">
          Optional. Attendance still uses the map boundary first.
        </p>
      )}
      {points.isPending ? (
        <p className="mt-3 text-xs text-slate-600">Loading saved access points…</p>
      ) : null}
      {points.isError ? (
        <p className="mt-2 text-xs text-red-700">
          Workplace Wi-Fi could not be loaded.
        </p>
      ) : null}
      {!points.isPending && !points.isError && rows.length === 0 ? (
        <p className="mt-3 text-xs leading-5 text-slate-600">{WORKPLACE_WIFI_EMPTY}</p>
      ) : null}
      {rows.length > 0 ? (
      <ul className="mt-3 space-y-2">
        {rows.map((row) => (
          <li
            key={row.id}
            className="flex flex-col gap-2 rounded-xl border border-slate-200 bg-white px-3 py-2 sm:flex-row sm:items-center sm:justify-between"
          >
            <div>
              <p className="text-sm font-medium text-slate-900">{row.label}</p>
              <p className="text-xs text-slate-500">
                Network: {row.ssid?.trim() ? row.ssid : "Name unavailable"}
              </p>
              <p className="text-xs text-slate-500">Wi-Fi address: {row.bssid}</p>
              <p className="text-xs text-slate-500">
                {row.enabled ? "Enabled" : "Disabled"}
              </p>
            </div>
            <div className="flex gap-2">
              <Button
                type="button"
                variant="outline"
                className="h-8 rounded-lg px-3 text-xs"
                disabled={toggle.isPending || remove.isPending}
                onClick={() => toggle.mutate({ id: row.id, enabled: !row.enabled })}
              >
                {row.enabled ? "Disable" : "Enable"}
              </Button>
              <Button
                type="button"
                variant="outline"
                className="h-8 rounded-lg px-3 text-xs"
                disabled={toggle.isPending || remove.isPending}
                onClick={() => remove.mutate(row.id)}
              >
                Remove
              </Button>
            </div>
          </li>
        ))}
      </ul>
      ) : null}
    </section>
  );
}
