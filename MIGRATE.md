# Moving this engine into the new frontend repo

Run these four lines **from inside the new repo**, on a clean working tree.

```bash
git remote add engine https://github.com/archivestudioz/Hackathon-Travel-Project-.git
git fetch engine main
git checkout engine/main -- supabase docs scripts content .env.example
git remote remove engine
```

Then commit:

```bash
git add supabase docs scripts content .env.example
git commit -m "Add the travel discovery engine"
git push
```

## What moves, and what does not

Only four directories plus `.env.example`. **Nothing the frontend owns is
touched** — not `package.json`, not `src/`, not `next.config`, `tsconfig`,
`eslint`, `postcss`, or the README. Verified by running the command above
against a scratch Next.js repo: every frontend file came back unmodified.

| Lands | Contents |
|---|---|
| `supabase/` | 12 migrations, 2 seeds, 6 dashboard-ready SQL files |
| `docs/` | API contract, typed client, fixtures, architecture, chat sheet |
| `scripts/` | Offline ingestion — Overpass, Tavily, Stay22, media |
| `content/` | Video catalogue and clip triage |

If `docs/frontend.md` comes across, delete it — it documents the previous
frontend and is the one file in `docs/` that is not engine material.

## Wiring it up — three steps

**1. Database.** Follow [`supabase/README.md`](supabase/README.md): six pastes
into the dashboard SQL editor, then enable Anonymous auth. Expect
`3 cities · 36 experiences · 36 media`.

**2. Client.**

```bash
npm i @supabase/supabase-js
cp docs/roam-client.ts src/lib/roam.ts
```

```
NEXT_PUBLIC_SUPABASE_URL=https://YOUR-PROJECT.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJ...
```

The anon key is safe in the browser: it identifies the project, not the user.
Row Level Security decides what any caller can see and it is enforced inside
Postgres, so there is no way for a client to read another traveller\'s data.

**3. Call it.**

```ts
import { getSessionState, getFeed, saveExperience, buildItinerary } from \'@/lib/roam\'

const state = await getSessionState()   // route on state.next_screen
const cards = await getFeed()           // ExperienceCard[], already ranked
await saveExperience(cards[0].experience_id)
await buildItinerary()                  // saves -> day-by-day plan
```

36 RPCs, one card shape, no REST layer and no ORM. Every function in
`roam-client.ts` maps to one screen action.

## Build screens before touching the database

```bash
NEXT_PUBLIC_ROAM_FIXTURES=1 npm run dev
```

Every call returns a real recorded payload from `docs/fixtures.ts`, dumped from
the seeded database rather than hand-written, so the shapes cannot drift.
Components never learn whether the data is live — removing the flag is the
entire migration. Bind Figma-generated components to `ExperienceCard` from the
first commit and there is no later refactor of every card.

## The AI chat sheet

`docs/itinerary-agent.ts` and `docs/itinerary-chat-route.ts` are the only
server-side pieces, and they exist for one reason: an Anthropic key cannot ship
to a browser.

```bash
npm i @anthropic-ai/sdk zod
cp docs/itinerary-agent.ts      src/lib/itinerary-agent.ts
cp docs/itinerary-chat-route.ts src/app/api/itinerary/chat/route.ts
echo \'ANTHROPIC_API_KEY=sk-ant-...\' >> .env.local    # NOT NEXT_PUBLIC_
```

Full reference: [`docs/api-contract.md`](docs/api-contract.md) and
[`docs/backend-features.md`](docs/backend-features.md).
