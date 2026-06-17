export const DOCUMENT_LABELS: Record<string, string> = {
  business_permit: "Business Permit",
  valid_id: "Valid ID of Owner",
  dti_sec: "DTI or SEC Registration",
  bir_cor: "BIR Certificate of Registration",
};

export const DOCUMENT_FIELDS = [
  { key: "business_permit", label: "Business Permit" },
  { key: "valid_id", label: "Valid ID of Owner" },
  { key: "dti_sec", label: "DTI or SEC Registration" },
  { key: "bir_cor", label: "BIR Certificate of Registration" },
] as const;

export type DocumentKey = (typeof DOCUMENT_FIELDS)[number]["key"];

export function formatBusinessType(type: string | null | undefined) {
  if (!type) return "Not specified";
  const normalized = type.toLowerCase();
  if (normalized === "restaurant") return "Restaurant";
  if (normalized === "cafe") return "Cafe";
  return type;
}

export function formatFileSize(bytes: number) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

export function formatVerificationStatus(status: string) {
  if (status === "pending") return "Pending Verification";
  if (status === "approved") return "Approved";
  if (status === "rejected") return "Rejected";
  if (status === "draft") return "Draft";
  return status.replace(/_/g, " ");
}
