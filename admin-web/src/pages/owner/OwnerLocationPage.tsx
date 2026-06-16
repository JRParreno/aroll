import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { getBusinessLocation, updateBusinessLocation } from "@/lib/api";

export function OwnerLocationPage() {
  const qc = useQueryClient();
  const [form, setForm] = useState({
    label: "Main",
    address: "",
    latitude: "",
    longitude: "",
    geofence_radius_m: "75",
  });

  const { data: location, isLoading } = useQuery({
    queryKey: ["business-location"],
    queryFn: getBusinessLocation,
  });

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

  const save = useMutation({
    mutationFn: () =>
      updateBusinessLocation({
        label: form.label,
        address: form.address,
        latitude: form.latitude ? Number(form.latitude) : null,
        longitude: form.longitude ? Number(form.longitude) : null,
        geofence_radius_m: Number(form.geofence_radius_m),
      }),
    onSuccess: () => {
      toast.success("Business location saved");
      qc.invalidateQueries({ queryKey: ["business-location"] });
      qc.invalidateQueries({ queryKey: ["setup-status"] });
    },
    onError: () => toast.error("Failed to save location"),
  });

  const canSave =
    form.address.trim().length >= 5 &&
    form.latitude !== "" &&
    form.longitude !== "" &&
    Number(form.geofence_radius_m) >= 20 &&
    Number(form.geofence_radius_m) <= 200;

  return (
    <div className="min-h-full bg-muted/30 p-6">
      <div className="mx-auto max-w-3xl space-y-6">
        <div>
          <h1 className="text-2xl font-semibold">Business Location</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Set your primary work site and geofence for attendance clock-in.
          </p>
        </div>

        <Card>
          <CardHeader>
            <CardTitle>Location & Geofence</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            {isLoading ? (
              <p className="text-sm text-muted-foreground">Loading…</p>
            ) : (
              <>
                <div className="space-y-2">
                  <Label htmlFor="location-address">Address</Label>
                  <Input
                    id="location-address"
                    value={form.address}
                    onChange={(e) =>
                      setForm({ ...form, address: e.target.value })
                    }
                    placeholder="123 Main St, Manila"
                  />
                </div>

                <div className="grid gap-4 sm:grid-cols-2">
                  <div className="space-y-2">
                    <Label htmlFor="location-latitude">Latitude</Label>
                    <Input
                      id="location-latitude"
                      type="number"
                      step="any"
                      value={form.latitude}
                      onChange={(e) =>
                        setForm({ ...form, latitude: e.target.value })
                      }
                      placeholder="14.5995"
                    />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="location-longitude">Longitude</Label>
                    <Input
                      id="location-longitude"
                      type="number"
                      step="any"
                      value={form.longitude}
                      onChange={(e) =>
                        setForm({ ...form, longitude: e.target.value })
                      }
                      placeholder="120.9842"
                    />
                  </div>
                </div>

                <div className="space-y-2">
                  <Label htmlFor="location-geofence">
                    Geofence Radius: {form.geofence_radius_m}m
                  </Label>
                  <input
                    id="location-geofence"
                    type="range"
                    min={20}
                    max={200}
                    step={5}
                    value={form.geofence_radius_m}
                    onChange={(e) =>
                      setForm({ ...form, geofence_radius_m: e.target.value })
                    }
                    className="w-full"
                  />
                  <p className="text-xs text-muted-foreground">
                    Allowed range: 20m – 200m (default 75m)
                  </p>
                </div>

                <Button
                  onClick={() => save.mutate()}
                  disabled={!canSave || save.isPending}
                >
                  Save Location
                </Button>
              </>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
