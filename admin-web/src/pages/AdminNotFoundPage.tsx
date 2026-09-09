import { Link } from "react-router-dom";
import { ArrowLeft, FileQuestion, Home } from "lucide-react";
import {
  AdminPage,
  AdminPageContent,
  AdminPageHeader,
} from "@/components/admin/layout/AdminPageLayout";
import { Button } from "@/components/ui/button";

export function AdminNotFoundPage() {
  return (
    <AdminPage>
      <AdminPageHeader
        title="Page not found"
        description="The page you're looking for doesn't exist or may have been moved. Check the URL or return to the dashboard."
      />
      <AdminPageContent>
        <div className="flex justify-center py-10">
          <div className="w-full max-w-lg text-center">
            <div className="owner-icon-well mx-auto h-16 w-16">
              <FileQuestion className="h-8 w-8" />
            </div>

            <p className="mt-6 text-6xl font-semibold tracking-tight text-[#1E3A5F]">
              404
            </p>

            <div className="mt-8 flex flex-wrap items-center justify-center gap-3">
              <Button
                asChild
                className="h-10 rounded-xl bg-[#1E3A5F] hover:bg-[#284B73]"
              >
                <Link to="/admin/dashboard">
                  <Home className="mr-2 h-4 w-4" />
                  Go to Dashboard
                </Link>
              </Button>
              <Button variant="outline" className="h-10 rounded-xl" asChild>
                <Link to="/admin/registrations">
                  <ArrowLeft className="mr-2 h-4 w-4" />
                  Registration Requests
                </Link>
              </Button>
            </div>
          </div>
        </div>
      </AdminPageContent>
    </AdminPage>
  );
}
