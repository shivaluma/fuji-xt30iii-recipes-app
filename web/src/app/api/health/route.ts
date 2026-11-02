import { connection } from "next/server";
import { listRecipes } from "@/lib/server/db";

/** Health check for Dokploy/Docker: verifies the app is up and the SQLite volume is readable. */
export async function GET() {
  await connection();
  try {
    listRecipes({ limit: 1 });
    return Response.json({ ok: true });
  } catch (error) {
    return Response.json({ ok: false, error: String(error) }, { status: 503 });
  }
}
