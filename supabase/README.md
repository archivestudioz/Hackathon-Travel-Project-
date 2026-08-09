# Standing the database up

Six pastes into the Supabase dashboard SQL editor, in this order. Every line in
every file is under 100 characters — long lines are what corrupted the earlier
attempts, not file size.

| # | File | What |
|---|---|---|
| 1 | `part1_schema.sql` | Tables, enums, triggers |
| 2 | `part2_engine.sql` | Scoring, action surface, RLS, age bands |
| 3 | `part3_features.sql` | Cold start, guest mode, accounts, planner |
| 4 | `rows_1_places.sql` | Countries, interests, cities, neighbourhoods, hosts |
| 5 | `rows_2_experiences.sql` | 36 experiences |
| 6 | `rows_3_media.sql` | 36 media rows |

Then **Authentication -> Providers -> Anonymous -> enable**. Nothing works
without it.

Check:

```sql
select (select count(*) from cities)            cities,
       (select count(*) from experiences)       experiences,
       (select count(*) from experience_media)  media;
```

Expect `3 · 36 · 36`.

Steps 4-6 carry `on conflict do nothing`, so re-running one after a partial
paste is safe. Steps 1-3 are not re-runnable; if you need to start over, run

```sql
drop schema if exists public cascade;
create schema public;
grant usage on schema public to postgres, anon, authenticated, service_role;
grant all on schema public to postgres, service_role;
```

`migrations/`, `seed.sql` and `seed_catalog.sql` are the source of truth the six
files above were generated from. Use them with `psql` if you have it; the six
files exist because the dashboard editor is the only route on a Windows box.
