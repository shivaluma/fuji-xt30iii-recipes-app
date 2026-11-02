import type { Metadata } from "next";
import { AdminClient } from "./admin-client";

export const metadata: Metadata = { title: "Admin", robots: { index: false, follow: false } };

export default function AdminPage() {
  return (
    <div className="mx-auto max-w-6xl px-5 pb-20 pt-28">
      <h1 className="mb-6 text-4xl font-bold tracking-tight">Admin</h1>
      <AdminClient />
    </div>
  );
}
