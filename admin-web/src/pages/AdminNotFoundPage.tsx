import { Link } from "react-router-dom";
import { ArrowLeft, FileQuestion, Home } from "lucide-react";
import { Button } from "@/components/ui/button";

export function AdminNotFoundPage() {
  return (
    <div className="flex min-h-full items-center justify-center bg-muted/30 p-6">
      <div className="w-full max-w-lg text-center">
        <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-2xl bg-primary/10 text-primary">
          <FileQuestion className="h-8 w-8" />
        </div>

        <p className="mt-6 text-6xl font-bold tracking-tight text-[#1e3a5f]">404</p>
        <h1 className="mt-2 text-xl font-semibold">Page not found</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          The page you&apos;re looking for doesn&apos;t exist or may have been moved.
          Check the URL or return to the dashboard.
        </p>

        <div className="mt-8 flex flex-wrap items-center justify-center gap-3">
          <Button asChild>
            <Link to="/admin/dashboard">
              <Home className="mr-2 h-4 w-4" />
              Go to Dashboard
            </Link>
          </Button>
          <Button variant="outline" asChild>
            <Link to="/admin/registrations">
              <ArrowLeft className="mr-2 h-4 w-4" />
              Registration Requests
            </Link>
          </Button>
        </div>
      </div>
    </div>
  );
}
