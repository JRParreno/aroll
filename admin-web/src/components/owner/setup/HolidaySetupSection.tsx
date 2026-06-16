import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  createHoliday,
  deleteHoliday,
  listHolidays,
  seedDefaultHolidays,
  updateHoliday,
  type Holiday,
} from "@/lib/api";

function isCustomHoliday(holiday: Holiday) {
  return holiday.holiday_type === "company";
}

export function HolidaySetupSection() {
  const qc = useQueryClient();
  const [customForm, setCustomForm] = useState({
    name: "",
    holiday_date: "",
    pay_multiplier: "1.0",
    is_paid: true,
  });
  const [editingId, setEditingId] = useState<string | null>(null);
  const [seedAttempted, setSeedAttempted] = useState(false);

  const { data: holidays = [], isLoading, isError } = useQuery({
    queryKey: ["holidays"],
    queryFn: listHolidays,
  });

  const seedDefaults = useMutation({
    mutationFn: seedDefaultHolidays,
    onSuccess: (created) => {
      if (created.length > 0) {
        toast.success(`Loaded ${created.length} Philippine holidays`);
      }
      qc.invalidateQueries({ queryKey: ["holidays"] });
      qc.invalidateQueries({ queryKey: ["setup-status"] });
    },
    onError: () => toast.error("Failed to load default holidays"),
  });

  useEffect(() => {
    if (!isLoading && holidays.length === 0 && !seedAttempted) {
      setSeedAttempted(true);
      seedDefaults.mutate();
    }
  }, [isLoading, holidays.length, seedAttempted]);

  const updateRow = useMutation({
    mutationFn: ({
      id,
      payload,
    }: {
      id: string;
      payload: {
        is_paid?: boolean;
        pay_multiplier?: number;
        name?: string;
        holiday_date?: string;
      };
    }) => updateHoliday(id, payload),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["holidays"] });
      qc.invalidateQueries({ queryKey: ["setup-status"] });
    },
    onError: () => toast.error("Failed to update holiday"),
  });

  const addCustom = useMutation({
    mutationFn: () => {
      const multiplier = Number(customForm.pay_multiplier);
      if (!customForm.name.trim()) {
        throw new Error("Name required");
      }
      if (!customForm.holiday_date) {
        throw new Error("Date required");
      }
      if (multiplier <= 0) {
        throw new Error("Multiplier must be greater than 0");
      }
      return createHoliday({
        name: customForm.name.trim(),
        holiday_date: customForm.holiday_date,
        is_paid: customForm.is_paid,
        pay_multiplier: multiplier,
        holiday_type: "company",
      });
    },
    onSuccess: () => {
      toast.success("Custom holiday added");
      setCustomForm({
        name: "",
        holiday_date: "",
        pay_multiplier: "1.0",
        is_paid: true,
      });
      qc.invalidateQueries({ queryKey: ["holidays"] });
      qc.invalidateQueries({ queryKey: ["setup-status"] });
    },
    onError: (error: Error) => toast.error(error.message || "Failed to add holiday"),
  });

  const removeCustom = useMutation({
    mutationFn: deleteHoliday,
    onSuccess: () => {
      toast.success("Custom holiday removed");
      setEditingId(null);
      qc.invalidateQueries({ queryKey: ["holidays"] });
      qc.invalidateQueries({ queryKey: ["setup-status"] });
    },
    onError: () => toast.error("Failed to delete holiday"),
  });

  function handleMultiplierChange(holiday: Holiday, value: string) {
    const multiplier = Number(value);
    if (Number.isNaN(multiplier) || multiplier <= 0) {
      toast.error("Pay multiplier must be greater than 0");
      return;
    }
    updateRow.mutate({
      id: holiday.id,
      payload: { pay_multiplier: multiplier },
    });
  }

  return (
    <div className="space-y-6">
      <p className="text-sm text-muted-foreground">
        Configure Philippine default holidays and custom company holidays. Turn a
        holiday off to skip holiday pay. Step completes once holidays are loaded,
        even if some are disabled.
      </p>

      {isLoading && (
        <p className="text-sm text-muted-foreground">Loading holidays…</p>
      )}
      {isError && (
        <p className="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
          Unable to load holidays.
        </p>
      )}

      {!isLoading && holidays.length > 0 && (
        <div className="overflow-x-auto rounded-md border">
          <table className="w-full min-w-[640px] text-sm">
            <thead className="bg-muted/50 text-left">
              <tr>
                <th className="px-3 py-2 font-medium">Name</th>
                <th className="px-3 py-2 font-medium">Date</th>
                <th className="px-3 py-2 font-medium">Enabled</th>
                <th className="px-3 py-2 font-medium">Pay Rate</th>
                <th className="px-3 py-2 font-medium">Actions</th>
              </tr>
            </thead>
            <tbody>
              {holidays.map((holiday) => (
                <tr key={holiday.id} className="border-t align-middle">
                  <td className="px-3 py-2">
                    {editingId === holiday.id && isCustomHoliday(holiday) ? (
                      <Input
                        defaultValue={holiday.name}
                        onBlur={(e) => {
                          if (e.target.value.trim() && e.target.value !== holiday.name) {
                            updateRow.mutate({
                              id: holiday.id,
                              payload: { name: e.target.value.trim() },
                            });
                          }
                        }}
                      />
                    ) : (
                      <div>
                        <p className="font-medium">{holiday.name}</p>
                        <p className="text-xs text-muted-foreground">
                          {isCustomHoliday(holiday) ? "Custom" : "Default PH"}
                        </p>
                      </div>
                    )}
                  </td>
                  <td className="px-3 py-2">
                    {editingId === holiday.id && isCustomHoliday(holiday) ? (
                      <Input
                        type="date"
                        defaultValue={holiday.holiday_date}
                        onBlur={(e) => {
                          if (e.target.value && e.target.value !== holiday.holiday_date) {
                            updateRow.mutate({
                              id: holiday.id,
                              payload: { holiday_date: e.target.value },
                            });
                          }
                        }}
                      />
                    ) : (
                      holiday.holiday_date
                    )}
                  </td>
                  <td className="px-3 py-2">
                    <label className="inline-flex items-center gap-2">
                      <input
                        type="checkbox"
                        checked={holiday.is_paid}
                        onChange={(e) =>
                          updateRow.mutate({
                            id: holiday.id,
                            payload: { is_paid: e.target.checked },
                          })
                        }
                      />
                      <span>{holiday.is_paid ? "ON" : "OFF"}</span>
                    </label>
                  </td>
                  <td className="px-3 py-2">
                    <Input
                      type="number"
                      step="0.1"
                      min="0.01"
                      className={`w-24 ${!holiday.is_paid ? "opacity-50" : ""}`}
                      defaultValue={holiday.pay_multiplier}
                      disabled={!holiday.is_paid || updateRow.isPending}
                      onBlur={(e) => handleMultiplierChange(holiday, e.target.value)}
                    />
                  </td>
                  <td className="px-3 py-2">
                    {isCustomHoliday(holiday) ? (
                      <div className="flex gap-2">
                        <Button
                          size="sm"
                          variant="outline"
                          onClick={() =>
                            setEditingId(editingId === holiday.id ? null : holiday.id)
                          }
                        >
                          {editingId === holiday.id ? "Done" : "Edit"}
                        </Button>
                        <Button
                          size="sm"
                          variant="outline"
                          onClick={() => removeCustom.mutate(holiday.id)}
                          disabled={removeCustom.isPending}
                        >
                          Delete
                        </Button>
                      </div>
                    ) : (
                      <span className="text-xs text-muted-foreground">—</span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <div className="rounded-lg border p-4 space-y-4">
        <p className="text-sm font-medium">Add Custom Holiday</p>
        <div className="grid gap-4 sm:grid-cols-2">
          <div className="space-y-2">
            <Label>Name</Label>
            <Input
              value={customForm.name}
              onChange={(e) =>
                setCustomForm({ ...customForm, name: e.target.value })
              }
              placeholder="Company Foundation Day"
            />
          </div>
          <div className="space-y-2">
            <Label>Date</Label>
            <Input
              type="date"
              value={customForm.holiday_date}
              onChange={(e) =>
                setCustomForm({ ...customForm, holiday_date: e.target.value })
              }
            />
          </div>
          <div className="space-y-2">
            <Label>Pay Multiplier</Label>
            <Input
              type="number"
              step="0.1"
              min="0.01"
              value={customForm.pay_multiplier}
              onChange={(e) =>
                setCustomForm({ ...customForm, pay_multiplier: e.target.value })
              }
              disabled={!customForm.is_paid}
              className={!customForm.is_paid ? "opacity-50" : undefined}
            />
          </div>
          <div className="flex items-end">
            <label className="flex items-center gap-2 text-sm">
              <input
                type="checkbox"
                checked={customForm.is_paid}
                onChange={(e) =>
                  setCustomForm({ ...customForm, is_paid: e.target.checked })
                }
              />
              Enabled (holiday pay applies)
            </label>
          </div>
        </div>
        <Button
          onClick={() => addCustom.mutate()}
          disabled={addCustom.isPending}
        >
          Add Custom Holiday
        </Button>
      </div>

      <Button
        variant="outline"
        onClick={() => seedDefaults.mutate()}
        disabled={seedDefaults.isPending}
      >
        Reload Philippine Holidays
      </Button>
    </div>
  );
}
