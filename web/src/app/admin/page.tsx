import type { Metadata } from "next";
import { AdminClient } from "./admin-client";

export const metadata: Metadata = { title: "Admin", robots: { index: false, follow: false } };

export default function AdminPage() {
  return (
    <div className="mx-auto max-w-6xl px-5 pt-12 sm:px-8 sm:pt-20 lg:px-10">
      <AdminClient />
    </div>
  );
}
