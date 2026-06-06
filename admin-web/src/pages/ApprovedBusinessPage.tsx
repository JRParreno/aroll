import { useQuery } from "@tanstack/react-query";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { listBusinesses } from "@/lib/api";

export function ApprovedBusinessPage() {
  const { data = [], isLoading } = useQuery({
    queryKey: ["businesses"],
    queryFn: listBusinesses,
  });

  return (
    <div className="p-6">
      <Card>
        <CardHeader>
          <CardTitle>Approved Businesses</CardTitle>
        </CardHeader>

        <CardContent className="space-y-3">
          {isLoading && <p>Loading...</p>}

          {!isLoading && data.length === 0 && (
            <p className="text-muted-foreground">No businesses found.</p>
          )}

          {data.map((b: any) => (
            <div key={b.id} className="border p-3 rounded-md">
              <p className="font-semibold">{b.name}</p>
              <p className="text-sm text-muted-foreground">
                Code: {b.business_code}
              </p>
              <p className="text-sm">Status: {b.status}</p>
            </div>
          ))}
        </CardContent>
      </Card>
    </div>
  );
}