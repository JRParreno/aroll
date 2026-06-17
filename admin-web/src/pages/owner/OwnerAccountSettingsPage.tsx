import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  changePassword,
  getAccountSettings,
  updateAccountSettings,
} from "@/lib/api";
import { ME_QUERY_KEY, setAuthSession } from "@/lib/authSession";

export function OwnerAccountSettingsPage() {
  const qc = useQueryClient();
  const [form, setForm] = useState({
    business_name: "",
    owner_name: "",
    email: "",
    contact_phone: "",
    address: "",
    business_type: "",
  });
  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");

  const { data, isLoading, isError } = useQuery({
    queryKey: ["account-settings"],
    queryFn: getAccountSettings,
  });

  useEffect(() => {
    if (!data) return;
    setForm({
      business_name: data.business_name,
      owner_name: data.owner_name ?? "",
      email: data.email,
      contact_phone: data.contact_phone ?? "",
      address: data.address,
      business_type: data.business_type ?? "",
    });
  }, [data]);

  const save = useMutation({
    mutationFn: () =>
      updateAccountSettings({
        business_name: form.business_name.trim(),
        owner_name: form.owner_name.trim(),
        contact_phone: form.contact_phone.trim() || null,
        address: form.address.trim(),
        business_type: form.business_type.trim() || null,
      }),
    onSuccess: () => {
      toast.success("Account settings saved");
      qc.invalidateQueries({ queryKey: ["account-settings"] });
      qc.invalidateQueries({ queryKey: ME_QUERY_KEY });
    },
    onError: () => toast.error("Failed to save account settings"),
  });

  const changePasswordMutation = useMutation({
    mutationFn: () => changePassword(currentPassword, newPassword),
    onSuccess: (res) => {
      setAuthSession(res.access_token);
      setCurrentPassword("");
      setNewPassword("");
      setConfirmPassword("");
      toast.success("Password updated");
    },
    onError: () => toast.error("Failed to update password"),
  });

  const canSave =
    form.business_name.trim().length >= 2 &&
    form.owner_name.trim().length >= 2 &&
    form.address.trim().length >= 5;

  const canChangePassword =
    currentPassword.length > 0 &&
    newPassword.length >= 8 &&
    newPassword === confirmPassword;

  return (
    <div className="min-h-full bg-muted/30 p-6">
      <div className="mx-auto max-w-3xl space-y-6">
        <div>
          <h1 className="text-2xl font-semibold">Account Settings</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Manage your personal, business, and contact information.
          </p>
        </div>

        {isLoading && (
          <p className="text-sm text-muted-foreground">Loading account settings…</p>
        )}
        {isError && (
          <p className="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
            Unable to load account settings.
          </p>
        )}

        {!isLoading && !isError && (
          <>
            <Card>
              <CardHeader>
                <CardTitle>Personal</CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="space-y-2">
                  <Label htmlFor="owner-name">Owner Name</Label>
                  <Input
                    id="owner-name"
                    value={form.owner_name}
                    onChange={(e) =>
                      setForm({ ...form, owner_name: e.target.value })
                    }
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="owner-email">Email</Label>
                  <Input id="owner-email" value={form.email} disabled />
                  <p className="text-xs text-muted-foreground">
                    Email cannot be changed here. Contact support if needed.
                  </p>
                </div>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle>Business</CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="space-y-2">
                  <Label htmlFor="business-name">Business Name</Label>
                  <Input
                    id="business-name"
                    value={form.business_name}
                    onChange={(e) =>
                      setForm({ ...form, business_name: e.target.value })
                    }
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="business-type">Business Type</Label>
                  <Input
                    id="business-type"
                    value={form.business_type}
                    onChange={(e) =>
                      setForm({ ...form, business_type: e.target.value })
                    }
                    placeholder="e.g. Cafe, Restaurant, Retail"
                  />
                </div>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle>Contact</CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="space-y-2">
                  <Label htmlFor="contact-phone">Contact Number</Label>
                  <Input
                    id="contact-phone"
                    value={form.contact_phone}
                    onChange={(e) =>
                      setForm({ ...form, contact_phone: e.target.value })
                    }
                    placeholder="+63 912 345 6789"
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="business-address">Business Address</Label>
                  <Input
                    id="business-address"
                    value={form.address}
                    onChange={(e) =>
                      setForm({ ...form, address: e.target.value })
                    }
                  />
                </div>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle>Security</CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="space-y-2">
                  <Label htmlFor="current-password">Current Password</Label>
                  <Input
                    id="current-password"
                    type="password"
                    value={currentPassword}
                    onChange={(e) => setCurrentPassword(e.target.value)}
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="new-password">New Password</Label>
                  <Input
                    id="new-password"
                    type="password"
                    value={newPassword}
                    onChange={(e) => setNewPassword(e.target.value)}
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="confirm-password">Confirm New Password</Label>
                  <Input
                    id="confirm-password"
                    type="password"
                    value={confirmPassword}
                    onChange={(e) => setConfirmPassword(e.target.value)}
                  />
                </div>
                <Button
                  variant="outline"
                  onClick={() => changePasswordMutation.mutate()}
                  disabled={!canChangePassword || changePasswordMutation.isPending}
                >
                  Update Password
                </Button>
              </CardContent>
            </Card>

            <Button
              onClick={() => save.mutate()}
              disabled={!canSave || save.isPending}
            >
              Save Changes
            </Button>
          </>
        )}
      </div>
    </div>
  );
}
