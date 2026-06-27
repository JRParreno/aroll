import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

export function OwnerComingSoon({ title }: { title: string }) {
  return (
    <div className="min-h-full bg-[#F7F8FA] p-6 sm:p-8">
      <div className="mx-auto max-w-6xl">
        <Card className="rounded-2xl border-slate-200 shadow-sm">
          <CardHeader>
            <CardTitle className="text-xl font-semibold text-[#1F2937]">
              {title}
            </CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-sm text-[#6B7280]">
              This module is ready for the next workflow pass.
            </p>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
