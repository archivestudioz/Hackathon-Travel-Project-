import {
  BUDGET_CEILINGS,
  CITY_LABELS,
  INTEREST_LABELS,
  type DismissedItem,
  type Experience,
  type InterestId,
  type MatchReason,
  type SavedItem,
  type ScoredExperience,
  type TravelerProfile,
} from "@/lib/types";
import { formatShortDate, nextOccurrence } from "@/lib/format";
import { EXPERIENCE_BY_ID } from "@/lib/data/experiences";

/**
 * A deterministic, explainable recommender.
 *
 * No machine learning: every point a card scores is attributable to a single
 * traveller-facing sentence, which is what the match chip renders. Same inputs
 * always produce the same ranking, so the demo is reproducible.
 */

/* Weights, in points. Tuned so interest + destination dominate, and an
 * explicit dismissal is heavy enough to visibly push a category down. */
const W = {
  interestPrimary: 30,
  interestExtra: 12,
  destination: 25,
  neighborhood: 8,
  datesTimeSensitive: 22,
  datesAvailable: 10,
  budgetFit: 14,
  budgetFree: 10,
  style: 12,
  savedAffinity: 14,
  dismissedPenalty: -26,
  keyword: 20,
  gem: 6,
  popularity: 4,
} as const;

/** Lets the match chip say "street food" rather than just "food". */
const TAG_INTEREST: Record<string, InterestId> = {
  "street food": "food",
  market: "food",
  tastings: "food",
  omakase: "food",
  kushikatsu: "food",
  breakfast: "food",
  coffee: "food",
  cafés: "food",
  "standing bars": "nightlife",
  rooftop: "nightlife",
  neon: "nightlife",
  "late night": "nightlife",
  "tiny bars": "nightlife",
  "digital art": "art",
  zines: "art",
  photography: "art",
  printing: "art",
  "retro gaming": "anime",
  tournament: "anime",
  "live music": "music",
  jazz: "music",
  djs: "music",
  indie: "music",
  "open jam": "music",
  hiking: "nature",
  "bamboo grove": "nature",
  sunrise: "nature",
  dawn: "nature",
  quiet: "nature",
  vintage: "shopping",
  fireworks: "festivals",
  festival: "festivals",
  boats: "festivals",
  "tea ceremony": "traditional",
  kimono: "traditional",
  sumo: "traditional",
  workshop: "traditional",
  machiya: "traditional",
  "old town": "traditional",
  "torii gates": "traditional",
};

const STOPWORDS = new Set([
  "i", "a", "an", "and", "the", "to", "of", "in", "on", "at", "for", "with", "my",
  "me", "we", "our", "is", "are", "am", "be", "it", "that", "this", "but", "or",
  "so", "if", "not", "no", "very", "really", "just", "like", "love", "want",
  "would", "rather", "prefer", "some", "any", "more", "less", "lot", "lots",
  "into", "about", "from", "than", "then", "there", "their", "they", "you",
  "japan", "japanese", "trip", "travel", "visit", "going", "go", "get", "see",
  "do", "doing", "things", "stuff", "place", "places", "avoid", "away", "too",
  "much", "little", "bit", "also", "well", "good", "great", "nice", "big",
]);

function tokenize(text: string): string[] {
  return Array.from(
    new Set(
      text
        .toLowerCase()
        .replace(/[^a-z\s-]/g, " ")
        .split(/\s+/)
        .map((t) => t.trim())
        .filter((t) => t.length > 3 && !STOPWORDS.has(t)),
    ),
  );
}

function searchableText(exp: Experience): string {
  return [
    exp.name,
    exp.neighborhood,
    exp.ward,
    exp.venue,
    exp.shortDescription,
    exp.description,
    ...exp.tags,
    ...exp.interests,
    exp.host.name,
  ]
    .join(" ")
    .toLowerCase();
}

/** Picks the most specific phrase available for an interest match. */
function interestPhrase(exp: Experience, interest: InterestId): string {
  for (const tag of exp.tags) {
    if (TAG_INTEREST[tag.toLowerCase()] === interest) return tag.toLowerCase();
  }
  return INTEREST_LABELS[interest].toLowerCase();
}

/** Tags that signal an experience suits (or does not suit) a travel style. */
function styleFit(exp: Experience, style: TravelerProfile["style"]): MatchReason | null {
  const tags = exp.tags.map((t) => t.toLowerCase()).join(" ");
  const notes = `${exp.accessNote} ${tags}`.toLowerCase();
  const ageRestricted = /\b(18\+|20\+|ages 20|ages 18)\b/.test(notes);

  switch (style) {
    case "solo":
      if (/small group|six people|very small|beginners welcome|open jam|standing/.test(tags))
        return { kind: "style", label: "Easy to join on your own", points: W.style };
      return null;
    case "couple":
      if (/sunset|couples popular|tea ceremony|kimono|counter dining|quiet|eight seats/.test(tags))
        return { kind: "style", label: "A good one for two", points: W.style };
      return null;
    case "family":
      if (ageRestricted || /not ideal for under|not suitable under/.test(notes))
        return { kind: "style", label: "Age-restricted", points: -W.style };
      if (exp.priceYen === 0 || /free|market|park|festival|workshop/.test(tags))
        return { kind: "style", label: "Works with the family", points: W.style };
      return null;
    case "group":
      if (/crawl|tour|multi-venue|tournament|standing|four shops|bar/.test(tags))
        return { kind: "style", label: "Built for a group", points: W.style };
      return null;
  }
}

export interface ScoreContext {
  profile: TravelerProfile;
  saved: SavedItem[];
  dismissed: DismissedItem[];
}

/** Interests the traveller has demonstrated a preference for by saving. */
function affinityFromActivity(items: { experienceId: string }[]): Map<InterestId, number> {
  const counts = new Map<InterestId, number>();
  for (const item of items) {
    const exp = EXPERIENCE_BY_ID[item.experienceId];
    if (!exp) continue;
    for (const i of exp.interests) counts.set(i, (counts.get(i) ?? 0) + 1);
  }
  return counts;
}

export function scoreExperience(exp: Experience, ctx: ScoreContext): ScoredExperience {
  const { profile } = ctx;
  const reasons: MatchReason[] = [];

  /* --- Interest overlap ------------------------------------------- */
  const matched = exp.interests.filter((i) => profile.interests.includes(i));
  if (matched.length > 0) {
    reasons.push({
      kind: "interest",
      label: `Because you like ${interestPhrase(exp, matched[0])}`,
      points: W.interestPrimary + (matched.length - 1) * W.interestExtra,
    });
  }

  /* --- Destination ------------------------------------------------- */
  if (profile.cities.includes(exp.city)) {
    reasons.push({
      kind: "destination",
      label: `In ${exp.neighborhood}, on your ${CITY_LABELS[exp.city]} list`,
      points: W.destination + W.neighborhood,
    });
  }

  /* --- Date compatibility ------------------------------------------ */
  const occurrence = nextOccurrence(exp, profile.dates);
  if (occurrence) {
    if (exp.schedule.kind === "oneoff") {
      reasons.push({
        kind: "dates",
        label: `Only on while you're here — ${formatShortDate(occurrence.date)}`,
        points: W.datesTimeSensitive,
      });
    } else {
      reasons.push({
        kind: "dates",
        label: `Runs during your ${CITY_LABELS[exp.city]} dates`,
        points: W.datesAvailable,
      });
    }
  }

  /* --- Budget ------------------------------------------------------ */
  const ceiling = BUDGET_CEILINGS[profile.budget];
  if (exp.priceYen === 0) {
    reasons.push({ kind: "budget", label: "Free to attend", points: W.budgetFree + W.budgetFit });
  } else if (exp.priceYen <= ceiling) {
    reasons.push({ kind: "budget", label: "Fits your budget", points: W.budgetFit });
  } else {
    reasons.push({ kind: "budget", label: "Above your usual budget", points: -W.budgetFit });
  }

  /* --- Travel style ------------------------------------------------ */
  const style = styleFit(exp, profile.style);
  if (style) reasons.push(style);

  /* --- Learned affinity from saves and dismissals ------------------- */
  const savedAffinity = affinityFromActivity(ctx.saved);
  const dismissedAffinity = affinityFromActivity(ctx.dismissed);
  for (const i of exp.interests) {
    const savedCount = savedAffinity.get(i) ?? 0;
    if (savedCount > 0) {
      reasons.push({
        kind: "affinity",
        label: `You've saved ${savedCount} other ${INTEREST_LABELS[i].toLowerCase()} ${
          savedCount === 1 ? "thing" : "things"
        }`,
        points: Math.min(savedCount, 3) * W.savedAffinity,
      });
      break;
    }
  }
  for (const i of exp.interests) {
    const dismissedCount = dismissedAffinity.get(i) ?? 0;
    if (dismissedCount >= 2) {
      reasons.push({
        kind: "affinity",
        label: `You've passed on ${INTEREST_LABELS[i].toLowerCase()} before`,
        points: W.dismissedPenalty,
      });
      break;
    }
  }

  /* --- Free-text description --------------------------------------- */
  if (profile.description.trim()) {
    const haystack = searchableText(exp);
    const hits = tokenize(profile.description).filter((t) => haystack.includes(t));
    if (hits.length > 0) {
      reasons.push({
        kind: "keyword",
        label: `You mentioned ${hits.slice(0, 2).map((h) => `“${h}”`).join(" and ")}`,
        points: Math.min(hits.length, 3) * W.keyword,
      });
    }
  }

  /* --- Local character and social proof ----------------------------- */
  if (exp.localGem) {
    reasons.push({ kind: "gem", label: "A local pick, not a tourist stop", points: W.gem });
  }
  const popularity = Math.min(W.popularity, Math.round(Math.log10(exp.saveCount + 1)));

  const score = reasons.reduce((sum, r) => sum + r.points, 0) + popularity;

  /* The chip shows the strongest positive reason. */
  const positives = [...reasons].filter((r) => r.points > 0).sort((a, b) => b.points - a.points);
  const headline = positives[0]?.label ?? "Popular with travellers in Japan";

  return { experience: exp, score, reasons, headline, occurrence };
}

export function rankExperiences(
  experiences: Experience[],
  ctx: ScoreContext,
): ScoredExperience[] {
  return experiences
    .map((e) => scoreExperience(e, ctx))
    /* Stable tiebreak on id keeps ordering reproducible across reloads. */
    .sort((a, b) => b.score - a.score || a.experience.id.localeCompare(b.experience.id));
}

/** The deck excludes anything already actioned. */
export function buildDeck(
  experiences: Experience[],
  ctx: ScoreContext,
): ScoredExperience[] {
  const seen = new Set([
    ...ctx.saved.map((s) => s.experienceId),
    ...ctx.dismissed.map((d) => d.experienceId),
  ]);
  return rankExperiences(
    experiences.filter((e) => !seen.has(e.id)),
    ctx,
  );
}
