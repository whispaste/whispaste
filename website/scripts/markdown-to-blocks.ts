/**
 * Isomorphic parser that turns a GitHub-release-body markdown string into a
 * structured {@link ReleaseBlocks} tree.
 *
 * The function is pure and isomorphic: it has no DOM, no filesystem, and no
 * Node-specific imports, so the exact same implementation runs at build-time
 * (consumed by `ReleaseStore`) and in the browser (consumed by
 * `ChangelogHydrator`).
 *
 * Parsing rules
 * -------------
 * - Sections start at lines matching `### Heading`. Everything before the
 *   first `###` line is treated as preamble (see "no heading" rule below).
 * - Bullet items are lines starting with `- ` or `* `. Within a section, each
 *   bullet becomes one `item`. The bullet's text may continue on indented
 *   continuation lines, which are folded into the item's `body`.
 * - When a bullet's text begins with `**Title**:` the bold-wrapped prefix is
 *   extracted as the item's `title` and the remainder becomes `body`.
 * - Known section headings are normalised to a canonical English form
 *   (e.g. `Verbesserungen` → `Improvements`). Unknown headings are preserved
 *   verbatim — they conceptually land in an "Other" bucket but the original
 *   text is what the caller renders.
 * - An empty section (heading followed by no bullets and no prose) keeps its
 *   heading and yields `items: []`.
 * - A body that contains no `###` heading at all is wrapped into a single
 *   default-heading section with one item whose `body` is the full input.
 *
 * @example
 *   const blocks = parseReleaseBody(`### Highlights\n- something\n`);
 *   // blocks.sections[0] === { heading: "Highlights", items: [{ body: "something" }] }
 */

/** A single bullet/paragraph within a section. */
export type ReleaseItem = {
  /** Optional bolded title prefix (`**Title**: body` syntax). */
  title?: string;
  /** Free-form item body — markdown allowed; never empty in practice. */
  body: string;
};

/** A `### Heading` block with its bullet items. */
export type ReleaseSection = {
  /** Canonical heading for known sections; original text for unknown ones. */
  heading: string;
  items: ReleaseItem[];
};

/** Structured representation of a release body. */
export type ReleaseBlocks = {
  sections: ReleaseSection[];
};

/** Heading used when the input contains no `### ...` headings at all. */
const DEFAULT_SECTION_HEADING = "Highlights";

/**
 * Map of lowercased source headings to canonical English headings. The map is
 * intentionally narrow — we only normalise the ones our PowerShell template
 * (`scripts/generate-release-notes.ps1`) and ad-hoc CHANGELOG entries use.
 */
const HEADING_ALIASES: ReadonlyMap<string, string> = new Map([
  ["highlights", "Highlights"],
  ["bug fixes", "Bug Fixes"],
  ["bugfixes", "Bug Fixes"],
  ["fixes", "Bug Fixes"],
  ["improvements", "Improvements"],
  ["verbesserungen", "Improvements"],
  ["enhancements", "Improvements"],
  ["removals", "Removals"],
  ["removed", "Removals"],
  ["observability", "Observability"],
  ["new features", "Highlights"],
  ["features", "Highlights"],
]);

/**
 * Parse a release-body markdown string into a structured block tree.
 *
 * Pure function: deterministic, no side effects, returns a fresh object on
 * every call so callers can safely mutate the result.
 */
export function parseReleaseBody(markdown: string): ReleaseBlocks {
  if (markdown.trim().length === 0) {
    return { sections: [] };
  }

  const lines = markdown.split(/\r?\n/);

  // First pass: split into raw sections by `### heading` lines.
  const rawSections: Array<{ heading: string | null; lines: string[] }> = [
    { heading: null, lines: [] },
  ];

  for (const line of lines) {
    const headingMatch = /^###\s+(.+?)\s*$/.exec(line);
    if (headingMatch) {
      rawSections.push({ heading: headingMatch[1] ?? "", lines: [] });
    } else {
      const current = rawSections[rawSections.length - 1];
      if (current) current.lines.push(line);
    }
  }

  // If no `###` headings were ever seen, wrap the whole body as one item in a
  // default section.
  const hasAnyHeading = rawSections.some((s) => s.heading !== null);
  if (!hasAnyHeading) {
    const body = rawSections[0]?.lines.join("\n").trim() ?? "";
    if (body.length === 0) return { sections: [] };
    return {
      sections: [{ heading: DEFAULT_SECTION_HEADING, items: [{ body }] }],
    };
  }

  // Drop the leading preamble bucket — anything before the first `###` is
  // discarded as preamble (typical for the PS template, which has no leading
  // prose). If it ever contains content we still ignore it; release notes are
  // section-structured by contract.
  const sectioned = rawSections.filter((s) => s.heading !== null) as Array<{
    heading: string;
    lines: string[];
  }>;

  return {
    sections: sectioned.map((s) => ({
      heading: canonicaliseHeading(s.heading),
      items: parseItems(s.lines),
    })),
  };
}

/**
 * Map a raw heading string to a canonical heading. Unknown headings are
 * returned unchanged (trimmed) so renderers can still display them.
 */
function canonicaliseHeading(raw: string): string {
  const trimmed = raw.trim();
  const alias = HEADING_ALIASES.get(trimmed.toLowerCase());
  return alias ?? trimmed;
}

/**
 * Parse the body lines of a single section into items.
 *
 * Recognises `- ` and `* ` as bullet markers. Indented continuation lines
 * (anything that doesn't itself start a new bullet, between bullets) are
 * appended to the current bullet's body. Blank lines are treated as item
 * separators only when not inside a continuation block — pragmatically we
 * just trim them out.
 */
function parseItems(lines: string[]): ReleaseItem[] {
  const items: ReleaseItem[] = [];
  let current: string[] | null = null;

  const flush = (): void => {
    if (current === null) return;
    const text = current.join("\n").trim();
    if (text.length > 0) {
      items.push(toItem(text));
    }
    current = null;
  };

  for (const line of lines) {
    const bulletMatch = /^\s*[-*]\s+(.*)$/.exec(line);
    if (bulletMatch) {
      flush();
      current = [bulletMatch[1] ?? ""];
      continue;
    }
    if (current !== null && line.trim().length > 0) {
      // Continuation of the current bullet (indented or wrapped prose).
      current.push(line.trim());
    }
    // Blank lines and pre-bullet prose are dropped — sections are
    // bullet-structured by contract.
  }
  flush();

  return items;
}

/**
 * Split a bullet's text into an optional bold title prefix and body.
 *
 * Recognises the shape `**Title**: rest of body`. Anything else becomes a
 * bare `{ body }` item.
 */
function toItem(text: string): ReleaseItem {
  const titleMatch = /^\*\*([^*]+)\*\*\s*:\s*(.*)$/s.exec(text);
  if (titleMatch && titleMatch[1] && titleMatch[2]) {
    const title = titleMatch[1].trim();
    const body = titleMatch[2].trim();
    if (title.length > 0 && body.length > 0) {
      return { title, body };
    }
  }
  return { body: text };
}
