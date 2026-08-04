import {
  OwnerPage,
  OwnerPageContent,
  OwnerPageHeader,
} from "@/components/owner/layout/OwnerPageLayout";
import { BusinessLocationSetup } from "@/components/owner/location/BusinessLocationSetup";

export function OwnerLocationPage() {
  return (
    <OwnerPage>
      <OwnerPageHeader
        title="Location"
        description="Set your workplace on the map and choose how close employees must be before they can clock in or clock out."
      />
      <OwnerPageContent>
        <BusinessLocationSetup />
      </OwnerPageContent>
    </OwnerPage>
  );
}
