# FilmLab Recipes — web showcase & backend

Next.js 16 (App Router, Cache Components) + shadcn/ui + SQLite (`node:sqlite`, built into Node 24).

- **Public site:** browse recipes, filter by film simulation, an approximate in-browser preview on a sample photo or your own (your photo never leaves the browser), and a "Download for FilmLab" JSON link.
- **Admin (`/admin`):** paste a token, then:
  - import a recipe from an image or text with AI (Claude), review it, and publish;
  - manage drafts and covers.
- **API:** used by the iOS app for "Extract with AI" and "Publish to Web".

Recipes use the **same JSON schema as the iOS app** (`src/lib/recipe/schema.ts` mirrors `FilmLab/Domain/Recipe/*.swift`). The browser preview is a port of the app's look engine, and `lut.test.ts` checks it against values exported from Swift.

## Develop

```sh
cp .env.example .env.local   # set ADMIN_TOKEN (and ANTHROPIC_API_KEY for AI import)
pnpm install
pnpm dev                     # http://localhost:3000 — seeds the 12 FilmLab starter recipes on first run
pnpm test && pnpm typecheck && pnpm lint && pnpm build
```

## Deploy on Dokploy

1. **Create → Application.** Choose the GitHub provider and pick `shivaluma/fuji-xt30iii-recipes-app`, branch `main`.
2. **Build type: Dockerfile.**
   - Build Path / Docker context: `web`
   - Dockerfile path: `Dockerfile`, relative to `web`
3. **Environment:**
   - `ADMIN_TOKEN`: a long random string, e.g. from `openssl rand -hex 32`. All writes and AI extraction require it.
   - `OPENROUTER_API_KEY`: needed only for AI import. It stays on the server and is never sent to browsers or the app.
     - The default model is `google/gemini-3.1-flash-lite` (see `bench/RESULTS.md`). Override it with `EXTRACTION_MODEL`.
     - Or set `EXTRACTION_PROVIDER=anthropic` + `ANTHROPIC_API_KEY`.
4. **Advanced › Volumes:** add a **volume mount** at `/app/data` (e.g. a named volume `filmlab-data`).
   - It holds the SQLite database and uploaded covers. Without it, every redeploy wipes your recipes.
   - If you use a bind mount instead, `chown -R 1001:1001` the host directory, because the container runs as uid 1001.
5. **Domains:** add your domain with **container port 3000** and enable HTTPS (Let's Encrypt).
6. **Replicas: keep 1.** SQLite lives on one volume; multiple replicas would each have their own database and cache.
7. Deploy. The image has a Docker `HEALTHCHECK` on `GET /api/health`, which also verifies the volume is readable.
   - You can point Dokploy's health check at the same path.

Alternatively, use Dokploy's **Docker Compose** type with `web/docker-compose.yml` (same env vars and volume).

After deploying, in the iOS app go to **Library › Settings › Web showcase**, enter `https://your-domain` and the same `ADMIN_TOKEN`, then tap **Save & Test Connection**.

## API

| Method | Path | Auth | Purpose |
|---|---|---|---|
| GET | `/api/health` | – | Liveness + database check |
| GET | `/api/recipes?sim=&q=` | – | Published recipes (`&all=1` with token includes drafts) |
| POST | `/api/recipes` | token | Create/update by id: `{recipe}` or `{document}` (FilmLab JSON), `status`, `body` |
| GET | `/api/recipes/:slug` | – | One recipe |
| PATCH | `/api/recipes/:slug` | token | `{status, body}` |
| DELETE | `/api/recipes/:slug` | token | Delete |
| GET | `/api/recipes/:slug/export` | – | FilmLab transfer JSON (import in the app) |
| POST | `/api/recipes/:slug/cover` | token | multipart `file` + `kind` = `photo` \| `camera-jpeg` \| `approximate-preview` |
| GET | `/api/media/:file` | – | Uploaded cover |
| POST | `/api/extract` | token | Image (multipart `file` or JSON `imageBase64`) and/or `text` → a **draft** plus `meta` (model, latency, tokens, cost). Nothing is stored or logged. Rate-limited to 30/hour. |

## Notes and limits

- **AI extraction**
  - Uses a provider-agnostic service (`src/lib/extract/`) with a strict JSON schema, a 25 s timeout, one retry for transient or invalid output, and validation of every response.
  - The model returns `null` for anything not visible, plus the raw source text for each field.
  - The server reports values that are *invalid* (range/step), *unsupported* on the X‑T30 III (e.g. Smooth Skin, Kelvin > 10000) or *not applicable* (e.g. Color on ACROS) without changing them.
  - A human reviews before publishing.
  - Benchmark: `bench/RESULTS.md`.
- **Copyright**
  - Recipe settings are facts. Credit the author (the draft keeps the credit it found).
  - Only upload cover images you own. The site labels covers as Photo, Camera JPEG or Approximate preview.
- **Unknown recipe URLs** render the not-found page with `noindex`. With Partial Prerendering the HTTP status is 200, because the shell streams first.
- **Caching:** public reads use `'use cache'` with tags, and writes call `revalidateTag(…, "max")`. The cache is in-memory per process (fine for one replica).
