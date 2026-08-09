# Dropping this engine into a different repo

One command, run from inside the NEW repo. Nothing is copied by hand and
nothing is downloaded.

```bash
git remote add engine https://github.com/archivestudioz/Hackathon-Travel-Project-.git
git fetch engine main
git checkout engine/main -- supabase docs scripts content
git remote remove engine
```

That lands four directories and touches nothing else — no package.json, no
src/, no config. The new frontend is untouched.

| Directory | What it is |
|---|---|
| `supabase/` | 12 migrations, 2 seeds, and `SETUP.sql` (whole database, one paste) |
| `docs/` | API contract, typed client, fixtures, architecture, the chat sheet |
| `scripts/` | Offline ingestion — Overpass, Tavily, Stay22, media attach |
| `content/` | Video catalog and the clip triage |

## Wiring the frontend to it — three steps

**1. Database.** Paste [`supabase/SETUP.sql`](supabase/SETUP.sql) into the
Supabase dashboard SQL editor and run it. It resets and rebuilds, so it is safe
over a half-applied database. Then **Authentication -> Providers -> Anonymous
-> enable**. Expect 36 experiences, 36 media rows, 3 cities.

**2. Client.**

```bash
npm i @supabase/supabase-js
cp docs/roam-client.ts src/lib/roam.ts
```

```
NEXT_PUBLIC_SUPABASE_URL=https://YOUR-PROJECT.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJ...
```

The anon key is safe in the browser. It identifies the project, not the user —
Row Level Security decides what any caller can see, and it is enforced inside
Postgres.

**3. Call it.**

```ts
import { getSessionState, getFeed, saveExperience, buildItinerary } from '@/lib/roam'

const state = await getSessionState()   // route on state.next_screen
const cards = await getFeed()           // ExperienceCard[], already ranked
await saveExperience(cards[0].experience_id)
await buildItinerary()                  // saves -> day-by-day plan
```

That is the whole integration. 36 RPCs, one card shape, no REST layer and no
ORM. Every function in `roam-client.ts` maps to one screen action.

## Build screens before the database exists

```bash
NEXT_PUBLIC_ROAM_FIXTURES=1 npm run dev
```

Every call then returns a real recorded payload from `docs/fixtures.ts`, dumped
from the seeded database rather than hand-written, so the shapes cannot drift.
Components never learn whether the data is live — removing the flag is the
entire migration.

Bind Figma-generated components to `ExperienceCard` from the first commit and
there is no later refactor of every card.

## The AI chat sheet

`docs/itinerary-agent.ts` and `docs/itinerary-chat-route.ts` are the only
server-side pieces, and they exist for one reason: an Anthropic key cannot ship
to a browser. Copy them to `src/lib/` and `src/app/api/itinerary/chat/route.ts`,
then:

```bash
npm i @anthropic-ai/sdk zod
echo 'ANTHROPIC_API_KEY=sk-ant-...' >> .env.local   # NOT NEXT_PUBLIC_
```

Full reference: [`docs/api-contract.md`](docs/api-contract.md) and
[`docs/backend-features.md`](docs/backend-features.md).
