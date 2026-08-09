-- Kyotei is 20+.
--
-- seed_catalog.sql adds Boat Race Suminoe, which is a public gambling venue
-- filed under `traditional` because there is no sports category and kyotei is a
-- seventy-year-old Japanese institution. Under the old rule that made it
-- visible to an under-18 account: is_adults_only() only recognised nightlife,
-- bars, clubs and alcohol, and a boat-race stadium is none of those.
--
-- Same class of bug as the Fushimi sake tasting, which reached minors because
-- it was categorised `food` and nobody had tagged it `alcohol`. The lesson held
-- both times: the age gate reads TAGS, so a tag that gates access is
-- load-bearing content, not decoration.

create or replace function is_adults_only(p_category text, p_tags text[])
returns boolean language sql immutable as $$
  select p_category = 'nightlife'
      or p_tags && array['nightlife', 'bar', 'club', 'alcohol', 'sake',
                         'izakaya', 'gambling'];
$$;
