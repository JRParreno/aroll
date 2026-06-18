import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

export function OwnerComingSoon({ title }: { title: string }) {
  return (
    <div className="min-h-full bg-muted/30 p-6">
      <div className="mx-auto max-w-6xl">
        <Card>
          <CardHeader>
            <CardTitle>{title}</CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-muted-foreground">Coming Soon</p>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
