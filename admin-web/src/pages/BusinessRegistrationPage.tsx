import { useState } from "react";
import { toast } from "sonner";
import { submitRegistration } from "@/lib/api";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

export function BusinessRegistrationPage() {
  const [form, setForm] = useState({
    business_name: "",
    owner_name: "",
    owner_email: "",
    owner_phone: "",
    proposed_address: "",
  });

  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);

    try {
      await submitRegistration(form);

      toast.success("Registration submitted successfully!");

      setForm({
        business_name: "",
        owner_name: "",
        owner_email: "",
        owner_phone: "",
        proposed_address: "",
      });
    } catch {
      toast.error("Failed to submit registration");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center p-4">
      <Card className="w-full max-w-xl">
        <CardHeader>
          <CardTitle>Business Registration</CardTitle>
        </CardHeader>

        <CardContent>
          <form onSubmit={handleSubmit} className="space-y-4">

            <div>
              <Label>Business Name</Label>
              <Input
                value={form.business_name}
                onChange={(e) =>
                  setForm({ ...form, business_name: e.target.value })
                }
              />
            </div>

            <div>
              <Label>Owner Name</Label>
              <Input
                value={form.owner_name}
                onChange={(e) =>
                  setForm({ ...form, owner_name: e.target.value })
                }
              />
            </div>

            <div>
              <Label>Owner Email</Label>
              <Input
                type="email"
                value={form.owner_email}
                onChange={(e) =>
                  setForm({ ...form, owner_email: e.target.value })
                }
              />
            </div>

            <div>
              <Label>Phone Number</Label>
              <Input
                value={form.owner_phone}
                onChange={(e) =>
                  setForm({ ...form, owner_phone: e.target.value })
                }
              />
            </div>

            <div>
              <Label>Business Address</Label>
              <Input
                value={form.proposed_address}
                onChange={(e) =>
                  setForm({ ...form, proposed_address: e.target.value })
                }
              />
            </div>

            <Button
              type="submit"
              className="w-full"
              disabled={loading}
            >
              {loading ? "Submitting..." : "Register Business"}
            </Button>
          </form>
        </CardContent>
      </Card>
    </div>
  );
}