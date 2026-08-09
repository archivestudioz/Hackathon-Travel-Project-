import type { CityId, InterestId, ScoredExperience, TravelerProfile } from "@/lib/types";
import { addDays, daysBetween, isWithin, occurrencesWithin, today } from "@/lib/format";

export interface ExploreFilters {
  query: string;
  cities: CityId[];
  interests: InterestId[];
  freeOnly: boolean;
  /** null means no ceiling. */
  maxPrice: number | null;
  /** Restricts to experiences running on this exact day. */
  onDate: string | null;
}

export function emptyFilters(): ExploreFilters {
  return { query: "", cities: [], interests: [], freeOnly: false, maxPrice: null, onDate: null };
}

export function activeFilterCount(f: ExploreFilters): number {
  return (
    (f.cities.length > 0 ? 1 : 0) +
    (f.interests.length > 0 ? 1 : 0) +
    (f.freeOnly ? 1 : 0) +
    (f.maxPrice !== null ? 1 : 0) +
    (f.onDate !== null ? 1 : 0)
  );
}

function matchesQuery(s: ScoredExperience, query: string): boolean {
  if (!query.trim()) return true;
  const q = query.trim().toLowerCase();
  const e = s.experience;
  return [e.name, e.neighborhood, e.ward, e.venue, e.shortDescription, e.host.name, ...e.tags, ...e.interests]
    .join(" ")
    .toLowerCase()
    .includes(q);
}

export function applyFilters(
  items: ScoredExperience[],
  filters: ExploreFilters,
  profile: TravelerProfile,
): ScoredExperience[] {
  return items.filter((s) => {
    const e = s.experience;
    if (!matchesQuery(s, filters.query)) return false;
    if (filters.cities.length > 0 && !filters.cities.includes(e.city)) return false;
    if (filters.interests.length > 0 && !e.interests.some((i) => filters.interests.includes(i)))
      return false;
    if ((filters.freeOnly || profile.freeOnly) && e.priceYen !== 0) return false;
    if (filters.maxPrice !== null && e.priceYen > filters.maxPrice) return false;
    if (filters.onDate) {
      const runs = occurrencesWithin(e, { start: filters.onDate, end: filters.onDate }, 1);
      if (runs.length === 0) return false;
    }
    return true;
  });
}

/* ------------------------------------------------------------------ */
/* Browse sections                                                     */
/* ------------------------------------------------------------------ */

export interface BrowseSection {
  id: string;
  title: string;
  caption: string;
  items: ScoredExperience[];
}

/** Builds the browse rows, skipping any that would render empty. */
export function buildSections(
  items: ScoredExperience[],
  profile: TravelerProfile,
): BrowseSection[] {
  const now = today();
  const weekEnd = addDays(now, 7);

  const thisWeek = items.filter((s) => {
    const runs = occurrencesWithin(s.experience, { start: now, end: weekEnd }, 1);
    return runs.length > 0;
  });

  const gems = items
    .filter((s) => s.experience.localGem)
    .sort((a, b) => b.score - a.score);

  const popular = [...items]
    .filter((s) => profile.cities.includes(s.experience.city))
    .sort((a, b) => b.experience.saveCount - a.experience.saveCount);

  /* The next Saturday and Sunday inside the traveller's window. */
  const weekendFree = items.filter((s) => {
    if (s.experience.priceYen !== 0) return false;
    const runs = occurrencesWithin(s.experience, { start: now, end: addDays(now, 14) }, 12);
    return runs.some((o) => {
      const day = new Date(o.date).getDay();
      return day === 0 || day === 6;
    });
  });

  const tripLength = Math.abs(daysBetween(profile.dates.start, profile.dates.end)) + 1;
  const duringTrip = items.filter(
    (s) => s.occurrence && isWithin(s.occurrence.date, profile.dates),
  );

  const sections: BrowseSection[] = [
    {
      id: "week",
      title: "Happening this week",
      caption: "On in the next seven days",
      items: thisWeek.slice(0, 10),
    },
    {
      id: "trip",
      title: "While you're here",
      caption: `Running across your ${tripLength} days`,
      items: duringTrip.slice(0, 10),
    },
    {
      id: "gems",
      title: "Hidden local gems",
      caption: "Community-run, low on the tourist trail",
      items: gems.slice(0, 10),
    },
    {
      id: "popular",
      title: "Popular near you",
      caption: "Most saved in your cities",
      items: popular.slice(0, 10),
    },
    {
      id: "free",
      title: "Free this weekend",
      caption: "Costs nothing to turn up",
      items: weekendFree.slice(0, 10),
    },
  ];

  return sections.filter((s) => s.items.length > 0);
}
