"use client";

import { Suspense, useEffect, useMemo, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { ChevronDown, List, Map as MapIcon, Search, SlidersHorizontal, X } from "lucide-react";
import { useApp } from "@/store/AppStore";
import { useUI } from "@/store/UIStore";
import { CITY_LABELS, type CityId } from "@/lib/types";
import { activeFilterCount, applyFilters, buildSections, emptyFilters, type ExploreFilters } from "@/lib/filters";
import { SwipeDeck } from "@/components/explore/SwipeDeck";
import { FilterSheet } from "@/components/explore/FilterSheet";
import { MapView } from "@/components/explore/MapView";
import { ListRow, RowCard, countdownBadge } from "@/components/explore/ExperienceCards";
import { Chip, EmptyState, Segmented, Skeleton } from "@/components/ui/primitives";
import { cn } from "@/lib/cn";

export default function ExplorePage() {
  return (
    <Suspense fallback={<ExploreFallback />}>
      <ExploreInner />
    </Suspense>
  );
}

function ExploreFallback() {
  return (
    <div className="flex flex-1 flex-col gap-3 p-3 pt-20">
      <Skeleton className="h-full w-full rounded-[28px] bg-black/5" />
    </div>
  );
}

type Mode = "deck" | "browse";
type BrowseView = "list" | "map";

function ExploreInner() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const { hydrated, deck, ranked, profile } = useApp();
  const { filtersOpen, setFiltersOpen } = useUI();

  const initialQuery = searchParams.get("q") ?? "";
  const [mode, setMode] = useState<Mode>(initialQuery ? "browse" : "deck");
  const [browseView, setBrowseView] = useState<BrowseView>("list");
  const [filters, setFilters] = useState<ExploreFilters>(() => ({
    ...emptyFilters(),
    query: initialQuery,
  }));
  const [cityMenuOpen, setCityMenuOpen] = useState(false);

  /* A tag tapped on the detail sheet arrives as ?q= and opens browse. */
  useEffect(() => {
    const q = searchParams.get("q");
    if (q) {
      setFilters((f) => ({ ...f, query: q }));
      setMode("browse");
    }
  }, [searchParams]);

  const deckItems = useMemo(
    () => applyFilters(deck, filters, profile),
    [deck, filters, profile],
  );
  const browseItems = useMemo(
    () => applyFilters(ranked, filters, profile),
    [ranked, filters, profile],
  );
  const sections = useMemo(() => buildSections(browseItems, profile), [browseItems, profile]);

  const filterCount = activeFilterCount(filters);
  const cityLabel =
    filters.cities.length === 1
      ? CITY_LABELS[filters.cities[0]]
      : filters.cities.length > 1
        ? `${filters.cities.length} cities`
        : "All cities";

  function selectCity(city: CityId | null) {
    setFilters((f) => ({ ...f, cities: city ? [city] : [] }));
    setCityMenuOpen(false);
  }

  function clearSearch() {
    setFilters((f) => ({ ...f, query: "" }));
    router.replace("/explore");
  }

  return (
    <div className="relative flex flex-1 flex-col overflow-hidden">
      {/* ------------------------------------------------------------ */}
      {/* Top bar                                                       */}
      {/* ------------------------------------------------------------ */}
      <div
        className={cn(
          "z-20 flex items-center gap-2 px-3 pt-[max(12px,env(safe-area-inset-top))] pb-2",
          mode === "deck" ? "absolute inset-x-0 top-0" : "sticky top-0 bg-base",
        )}
      >
        <div className="relative">
          <button
            onClick={() => setCityMenuOpen((o) => !o)}
            aria-expanded={cityMenuOpen}
            className={cn(
              "flex h-10 items-center gap-1 rounded-full px-3 text-[13.5px] font-semibold",
              "border border-line bg-white text-ink shadow-sm",
            )}
          >
            {cityLabel}
            <ChevronDown size={15} />
          </button>
          {cityMenuOpen && (
            <div className="absolute left-0 top-12 z-30 w-44 overflow-hidden rounded-[16px] border border-line bg-white shadow-xl">
              <button
                onClick={() => selectCity(null)}
                className="block w-full px-4 py-3 text-left text-[14px] font-medium text-ink hover:bg-sand"
              >
                All cities
              </button>
              {(profile.cities.length > 0 ? profile.cities : (["tokyo", "kyoto", "osaka"] as CityId[])).map(
                (c) => (
                  <button
                    key={c}
                    onClick={() => selectCity(c)}
                    className="block w-full border-t border-line px-4 py-3 text-left text-[14px] font-medium text-ink hover:bg-sand"
                  >
                    {CITY_LABELS[c]}
                  </button>
                ),
              )}
            </div>
          )}
        </div>

        <div className="flex-1 flex justify-center">
          <Segmented
            value={mode}
            onChange={setMode}
            options={[
              { value: "deck", label: "Deck" },
              { value: "browse", label: "Browse" },
            ]}
            className="shadow-sm"
          />
        </div>

        <button
          onClick={() => setFiltersOpen(true)}
          aria-label="Filters"
          className={cn(
            "relative flex h-10 w-10 items-center justify-center rounded-full",
            "border border-line bg-white text-ink shadow-sm",
          )}
        >
          <SlidersHorizontal size={17} />
          {filterCount > 0 && (
            <span className="absolute right-1.5 top-1.5 h-2 w-2 rounded-full bg-accent" />
          )}
        </button>
      </div>

      {/* ------------------------------------------------------------ */}
      {/* Deck                                                          */}
      {/* ------------------------------------------------------------ */}
      {mode === "deck" ? (
        <SwipeDeck
          deck={deckItems}
          loading={!hydrated}
          onBrowse={() => setMode("browse")}
          onLoosenFilters={() => {
            setFilters({ ...emptyFilters() });
            setFiltersOpen(true);
          }}
        />
      ) : (
        /* ---------------------------------------------------------- */
        /* Browse                                                      */
        /* ---------------------------------------------------------- */
        <div className="flex flex-1 flex-col overflow-hidden">
          <div className="sticky top-0 z-10 bg-base px-5 pb-2">
            <label className="relative block">
              <Search size={17} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-ink-faint" />
              <input
                value={filters.query}
                onChange={(e) => setFilters((f) => ({ ...f, query: e.target.value }))}
                placeholder="Search events, neighbourhoods, hosts…"
                aria-label="Search experiences"
                className="w-full rounded-full border border-line bg-white py-3 pl-10 pr-10 text-[14.5px] text-ink outline-none placeholder:text-ink-faint focus:border-accent"
              />
              {filters.query && (
                <button
                  onClick={clearSearch}
                  aria-label="Clear search"
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-ink-faint"
                >
                  <X size={17} />
                </button>
              )}
            </label>

            <div className="-mx-5 mt-2 flex gap-2 overflow-x-auto hide-scrollbar px-5">
              <Chip size="sm" selected={filters.freeOnly} onClick={() => setFilters((f) => ({ ...f, freeOnly: !f.freeOnly }))}>
                Free
              </Chip>
              <Chip size="sm" onClick={() => setFiltersOpen(true)}>
                Category {filters.interests.length > 0 && `· ${filters.interests.length}`}
              </Chip>
              <Chip size="sm" onClick={() => setFiltersOpen(true)}>
                Date {filters.onDate ? "· 1" : ""}
              </Chip>
              <Chip size="sm" onClick={() => setFiltersOpen(true)}>
                Price {filters.maxPrice ? `· ¥${filters.maxPrice.toLocaleString()}` : ""}
              </Chip>
              {filterCount > 0 && (
                <Chip size="sm" onClick={() => setFilters({ ...emptyFilters(), query: filters.query })}>
                  Clear all
                </Chip>
              )}
            </div>

            <div className="mt-2 flex justify-center">
              <div className="inline-flex rounded-full border border-line bg-white p-0.5">
                {(["list", "map"] as BrowseView[]).map((v) => (
                  <button
                    key={v}
                    onClick={() => setBrowseView(v)}
                    aria-pressed={browseView === v}
                    className={cn(
                      "inline-flex items-center gap-1.5 rounded-full px-3.5 py-1.5 text-[12.5px] font-semibold capitalize transition-colors",
                      browseView === v ? "bg-ink text-white" : "text-ink-soft",
                    )}
                  >
                    {v === "list" ? <List size={13} /> : <MapIcon size={13} />}
                    {v}
                  </button>
                ))}
              </div>
            </div>
          </div>

          {browseView === "map" ? (
            <MapView items={browseItems} />
          ) : (
            <div className="flex-1 overflow-y-auto pb-6 hide-scrollbar">
              {!hydrated ? (
                <div className="space-y-3 px-5 pt-3">
                  {[0, 1, 2, 3].map((i) => (
                    <Skeleton key={i} className="h-[116px] w-full rounded-[18px] bg-black/5" />
                  ))}
                </div>
              ) : browseItems.length === 0 ? (
                <EmptyState
                  icon={<Search size={24} />}
                  title="Nothing matches yet"
                  body="Try a different search, or clear the filters to see everything on during your trip."
                  action={{
                    label: "Clear filters",
                    onClick: () => setFilters(emptyFilters()),
                  }}
                />
              ) : filters.query.trim() ? (
                /* Search results as a flat list */
                <div className="space-y-2.5 px-5 pt-3">
                  <p className="text-[13px] font-medium text-ink-soft">
                    {browseItems.length} {browseItems.length === 1 ? "result" : "results"} for
                    &ldquo;{filters.query}&rdquo;
                  </p>
                  {browseItems.map((s) => (
                    <ListRow key={s.experience.id} scored={s} />
                  ))}
                </div>
              ) : (
                /* Curated sections */
                <div className="space-y-7 pt-3">
                  {sections.map((section) => (
                    <section key={section.id}>
                      <div className="mb-2.5 px-5">
                        <h2 className="font-display text-[21px] leading-tight tracking-tight text-ink">
                          {section.title}
                        </h2>
                        <p className="text-[12.5px] text-ink-soft">{section.caption}</p>
                      </div>
                      <div className="flex gap-3 overflow-x-auto hide-scrollbar px-5 pb-1">
                        {section.items.map((s) => (
                          <RowCard
                            key={s.experience.id}
                            scored={s}
                            badge={
                              section.id === "week"
                                ? countdownBadge(s)
                                : section.id === "gems"
                                  ? "Local pick"
                                  : section.id === "popular"
                                    ? `${s.experience.saveCount.toLocaleString()} saves`
                                    : undefined
                            }
                          />
                        ))}
                      </div>
                    </section>
                  ))}
                </div>
              )}
            </div>
          )}
        </div>
      )}

      <FilterSheet
        open={filtersOpen}
        onClose={() => setFiltersOpen(false)}
        filters={filters}
        onChange={setFilters}
        resultCount={browseItems.length}
      />
    </div>
  );
}
