import { z } from 'zod';

/**
 * Keyset (cursor) pagination for list endpoints.
 *
 * A cursor is the sort key (`created_at`/`uploaded_at`) plus the row id of
 * the last item on the previous page. Using the id as a tiebreaker keeps the
 * ordering total, so rows that share a timestamp are neither skipped nor
 * repeated across pages. Clients that send no `limit`/`cursor` get the full
 * list up to the supplied default limit, as before, plus a `nextCursor`
 * field they can ignore.
 */

export interface PageCursor {
  at: string;
  id: string;
}

export interface ResolvedPage {
  limit: number;
  cursor: PageCursor | null;
}

const pageQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).optional(),
  cursor: z.string().min(1).max(512).optional(),
});

export function encodeCursor(cursor: PageCursor): string {
  return Buffer.from(JSON.stringify([cursor.at, cursor.id]), 'utf8').toString('base64url');
}

export function decodeCursor(raw: string): PageCursor | null {
  try {
    const parsed: unknown = JSON.parse(Buffer.from(raw, 'base64url').toString('utf8'));
    if (
      Array.isArray(parsed) &&
      parsed.length === 2 &&
      typeof parsed[0] === 'string' &&
      typeof parsed[1] === 'string'
    ) {
      return { at: parsed[0], id: parsed[1] };
    }
  } catch {
    // fall through to null - a malformed cursor is a client error
  }
  return null;
}

/**
 * Parses `?limit=&cursor=` from a request query. Returns null for malformed
 * input so the caller can answer 400. A missing limit becomes `defaultLimit`;
 * larger requested limits are clamped to `maxLimit`.
 */
export function resolvePage(
  query: Record<string, unknown>,
  defaultLimit: number,
  maxLimit: number,
): ResolvedPage | null {
  const parsed = pageQuerySchema.safeParse(query);
  if (!parsed.success) return null;

  let cursor: PageCursor | null = null;
  if (parsed.data.cursor !== undefined) {
    cursor = decodeCursor(parsed.data.cursor);
    if (!cursor) return null;
  }

  const limit = Math.min(parsed.data.limit ?? defaultLimit, maxLimit);
  return { limit, cursor };
}

/**
 * SQL fragment restricting results to rows strictly after `cursor` in a
 * `ORDER BY <column> DESC, <idColumn> DESC` ordering. Column names are
 * fixed by the calling code, never taken from user input.
 */
export function keysetClause(
  column: string,
  idColumn: string,
  cursor: PageCursor | null,
): { sql: string; params: string[] } {
  if (!cursor) return { sql: '', params: [] };
  return {
    sql: `AND (${column} < ? OR (${column} = ? AND ${idColumn} < ?))`,
    params: [cursor.at, cursor.at, cursor.id],
  };
}

/**
 * Splits a page fetched with `LIMIT limit + 1` into the items to return and
 * the cursor for the next page (null when this was the last page).
 */
export function buildPage<T extends { id: string }>(
  rows: T[],
  limit: number,
  sortValue: (row: T) => string,
): { items: T[]; nextCursor: string | null } {
  if (rows.length <= limit) {
    return { items: rows, nextCursor: null };
  }
  const items = rows.slice(0, limit);
  const last = items[items.length - 1];
  return {
    items,
    nextCursor: encodeCursor({ at: sortValue(last), id: last.id }),
  };
}
