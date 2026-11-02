import { createClient, type SupabaseClient } from "@supabase/supabase-js";

// Changing settings requires a new SQL migration/version, not a silent cache hit.
export const ROUTING_VERSION = "geoapify-walk-short-metric-snap100-v1";
export const CANDIDATE_RADIUS_M = 11_000;
export const MAX_SNAP_M = 100;
const MAX_UNIVERSITIES = 16;
const DEFAULT_TIMEOUT_MS = 20_000;
const MATRIX_URL = "https://api.geoapify.com/v1/routematrix";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, x-client-info, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Cache-Control": "no-store",
};

export interface Point {
  latitude: number;
  longitude: number;
}

interface University extends Point {
  id: number;
}

interface RouteWrite {
  university_id: number;
  university_latitude: number;
  university_longitude: number;
  status: "ready" | "unroutable" | "needs_pin_review";
  distance_m: number | null;
  matched_source_latitude: number | null;
  matched_source_longitude: number | null;
  matched_target_latitude: number | null;
  matched_target_longitude: number | null;
}

export interface RefreshConfig {
  supabaseUrl: string;
  anonKey: string;
  serviceRoleKey: string;
  routingApiKey: () => string | undefined;
}

interface HandlerOptions {
  fetch?: typeof fetch;
  timeoutMs?: number;
}

class SafeError extends Error {
  constructor(readonly status: number, readonly code: string, message: string) {
    super(message);
  }
}

function response(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function record(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function finite(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

function point(latitude: unknown, longitude: unknown): Point | null {
  return finite(latitude) && Math.abs(latitude) <= 90 && finite(longitude) &&
      Math.abs(longitude) <= 180
    ? { latitude, longitude }
    : null;
}

function lonLat(value: unknown): Point | null {
  return Array.isArray(value) && value.length === 2 ? point(value[1], value[0]) : null;
}

export function greatCircleMeters(a: Point, b: Point): number {
  const radians = Math.PI / 180;
  const h = Math.sin((b.latitude - a.latitude) * radians / 2) ** 2 +
    Math.cos(a.latitude * radians) * Math.cos(b.latitude * radians) *
      Math.sin((b.longitude - a.longitude) * radians / 2) ** 2;
  return 12_742_017.6 * Math.asin(Math.sqrt(Math.min(1, Math.max(0, h))));
}

async function readJson(
  body: ReadableStream<Uint8Array> | null,
  maxBytes: number,
  signal: AbortSignal,
  invalid: SafeError,
): Promise<unknown> {
  if (!body) throw invalid;
  let bytes = 0;
  let text = "";
  const decoder = new TextDecoder("utf-8", { fatal: true });
  try {
    await body.pipeTo(
      new WritableStream<Uint8Array>({
        write(chunk) {
          bytes += chunk.byteLength;
          if (bytes > maxBytes) throw invalid;
          text += decoder.decode(chunk, { stream: true });
        },
      }),
      { signal },
    );
    return JSON.parse(text + decoder.decode());
  } catch {
    // Never forward parse/transport errors: they can contain URLs or credentials.
    throw invalid;
  }
}

function databaseResult<T>(result: { data: T; error: unknown }): T {
  if (result.error) {
    throw new SafeError(
      503,
      "database_unavailable",
      "Walking distances are temporarily unavailable.",
    );
  }
  return result.data;
}

function universitiesFrom(value: unknown): University[] {
  if (!Array.isArray(value) || value.length > MAX_UNIVERSITIES) {
    throw new SafeError(
      503,
      "catalogue_invalid",
      "The university catalogue needs administrator review.",
    );
  }
  const ids = new Set<number>();
  return value.map((row) => {
    const pin = record(row) ? point(row.latitude, row.longitude) : null;
    if (
      !record(row) || !pin || !Number.isInteger(row.id) || !finite(row.id) ||
      row.id < 1 || row.id > 2_147_483_647 || row.is_active !== true || ids.has(row.id)
    ) {
      throw new SafeError(
        503,
        "catalogue_invalid",
        "The university catalogue needs administrator review.",
      );
    }
    ids.add(row.id);
    return { id: row.id, ...pin };
  });
}

function currentRoute(
  row: unknown,
  listingId: string,
  source: Point,
  university: University,
): boolean {
  if (
    !record(row) || row.listing_id !== listingId || row.university_id !== university.id ||
    row.routing_version !== ROUTING_VERSION || row.listing_latitude !== source.latitude ||
    row.listing_longitude !== source.longitude || row.university_latitude !== university.latitude ||
    row.university_longitude !== university.longitude || typeof row.calculated_at !== "string" ||
    !Number.isFinite(Date.parse(row.calculated_at))
  ) return false;

  const matchedSource = point(row.matched_source_latitude, row.matched_source_longitude);
  const matchedTarget = point(row.matched_target_latitude, row.matched_target_longitude);
  const sourceAbsent = row.matched_source_latitude === null &&
    row.matched_source_longitude === null;
  const targetAbsent = row.matched_target_latitude === null &&
    row.matched_target_longitude === null;
  if ((!matchedSource && !sourceAbsent) || (!matchedTarget && !targetAbsent)) return false;
  const sourceFar = matchedSource !== null && greatCircleMeters(source, matchedSource) > MAX_SNAP_M;
  const targetFar = matchedTarget !== null &&
    greatCircleMeters(university, matchedTarget) > MAX_SNAP_M;
  if (row.status === "ready") {
    return finite(row.distance_m) && row.distance_m >= 0 && matchedSource !== null &&
      matchedTarget !== null && !sourceFar && !targetFar;
  }
  return row.distance_m === null &&
    ((row.status === "unroutable" && !sourceFar && !targetFar) ||
      (row.status === "needs_pin_review" && (sourceFar || targetFar)));
}

function matrixRoutes(value: unknown, source: Point, targets: University[]): RouteWrite[] {
  const invalid = new SafeError(
    502,
    "routing_invalid_response",
    "The routing provider returned unusable data.",
  );
  if (
    !record(value) || value.units !== "metric" || value.distance_units !== "meters" ||
    value.mode !== "walk" || (value.type !== undefined && value.type !== "short") ||
    !Array.isArray(value.sources) || value.sources.length !== 1 || !Array.isArray(value.targets) ||
    value.targets.length !== targets.length || !Array.isArray(value.sources_to_targets) ||
    value.sources_to_targets.length !== 1 || !Array.isArray(value.sources_to_targets[0]) ||
    value.sources_to_targets[0].length !== targets.length
  ) throw invalid;

  const matched = (entry: unknown, expected: Point): Point | null => {
    if (!record(entry)) throw invalid;
    const original = lonLat(entry.original_location);
    // Provider originals may be decimal-rounded; never use them as DB snapshots.
    if (
      !original || Math.abs(original.latitude - expected.latitude) > 1e-7 ||
      Math.abs(original.longitude - expected.longitude) > 1e-7
    ) throw invalid;
    if (entry.location === undefined) return null; // Documented for an unmatched waypoint.
    const pin = lonLat(entry.location);
    if (!pin) throw invalid;
    return pin;
  };

  const matchedSource = matched(value.sources[0], source);
  const entries: unknown[] = value.targets;
  const cells: unknown[] = value.sources_to_targets[0];
  return targets.map((target, index) => {
    const cell = cells[index];
    if (
      !record(cell) || cell.source_index !== 0 || cell.target_index !== index ||
      !(cell.distance === null || (finite(cell.distance) && cell.distance >= 0)) ||
      !(cell.time === null || (finite(cell.time) && cell.time >= 0))
    ) throw invalid;

    const matchedTarget = matched(entries[index], target);
    const unreachable = cell.distance === null || cell.time === null;
    if (!unreachable && (!matchedSource || !matchedTarget)) throw invalid;
    const needsReview =
      (matchedSource !== null && greatCircleMeters(source, matchedSource) > MAX_SNAP_M) ||
      (matchedTarget !== null && greatCircleMeters(target, matchedTarget) > MAX_SNAP_M);
    return {
      university_id: target.id,
      university_latitude: target.latitude,
      university_longitude: target.longitude,
      status: needsReview ? "needs_pin_review" : unreachable ? "unroutable" : "ready",
      distance_m: needsReview || unreachable ? null : cell.distance as number,
      matched_source_latitude: matchedSource?.latitude ?? null,
      matched_source_longitude: matchedSource?.longitude ?? null,
      matched_target_latitude: matchedTarget?.latitude ?? null,
      matched_target_longitude: matchedTarget?.longitude ?? null,
    };
  });
}

export function createRefreshHandler(config: RefreshConfig, options: HandlerOptions = {}) {
  const transport = options.fetch ?? fetch;
  // Coalesce same-pin submissions within this isolate. Separate isolates may
  // both calculate; the locked SQL writer never replaces a current result.
  const inFlight = new Map<string, Promise<void>>();

  return async (request: Request): Promise<Response> => {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders });
    }
    if (request.method !== "POST") {
      return response(405, {
        code: "method_not_allowed",
        message: "Use POST to refresh walking distances.",
      });
    }
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), options.timeoutMs ?? DEFAULT_TIMEOUT_MS);
    const { signal } = controller;
    try {
      const authorization = request.headers.get("Authorization")?.match(/^Bearer ([^\s]+)$/i);
      if (!authorization) {
        throw new SafeError(401, "unauthorized", "Sign in before refreshing walking distances.");
      }
      if (
        request.headers.get("Content-Type")?.split(";")[0].trim().toLowerCase() !==
          "application/json"
      ) {
        throw new SafeError(
          415,
          "invalid_request",
          "Send a JSON object containing only listing_id.",
        );
      }
      const body = await readJson(
        request.body,
        1024,
        signal,
        new SafeError(
          400,
          "invalid_request",
          "Send a JSON object containing only a valid listing_id.",
        ),
      );
      if (
        !record(body) || Object.keys(body).length !== 1 || typeof body.listing_id !== "string" ||
        !UUID.test(body.listing_id)
      ) {
        throw new SafeError(
          400,
          "invalid_request",
          "Send a JSON object containing only a valid listing_id.",
        );
      }
      if (!config.supabaseUrl || !config.anonKey || !config.serviceRoleKey) {
        throw new SafeError(
          503,
          "service_not_configured",
          "Walking distance refresh is not configured.",
        );
      }
      const listingId = body.listing_id.toLowerCase();
      const token = authorization[1];
      const boundedFetch: typeof fetch = (input, init) =>
        transport(input, { ...init, signal, redirect: "error" });
      const caller = createClient(config.supabaseUrl, config.anonKey, {
        global: { headers: { Authorization: `Bearer ${token}` }, fetch: boundedFetch },
        db: { retry: false },
        auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
      });
      const identity = await caller.auth.getUser(token);
      if (identity.error || !identity.data.user) {
        if (
          identity.error && identity.error.status !== 401 && identity.error.status !== 403 &&
          identity.error.status !== 400
        ) {
          throw new SafeError(
            503,
            "authentication_unavailable",
            "Sign-in verification is temporarily unavailable.",
          );
        }
        throw new SafeError(401, "unauthorized", "Sign in before refreshing walking distances.");
      }
      const userId = identity.data.user.id;
      const profile: unknown = databaseResult(
        await caller.from("profiles").select("id,role")
          .eq("id", userId).maybeSingle(),
      );
      if (!record(profile) || profile.id !== userId || profile.role !== "landlord") {
        throw new SafeError(
          403,
          "landlord_role_required",
          "Only the owning landlord may refresh walking distances.",
        );
      }
      const listing: unknown = databaseResult(
        await caller.from("listings")
          .select("id,landlord_id,latitude,longitude").eq("id", listingId).eq("landlord_id", userId)
          .maybeSingle(),
      );
      if (!record(listing) || listing.id !== listingId || listing.landlord_id !== userId) {
        throw new SafeError(
          404,
          "listing_not_accessible",
          "This property is unavailable to this account.",
        );
      }
      const source = point(listing.latitude, listing.longitude);
      if (!source) {
        throw new SafeError(
          409,
          "listing_pin_required",
          "Save a valid property pin before refreshing distances.",
        );
      }

      const key = `${userId}:${listingId}:${source.latitude}:${source.longitude}`;
      let pending = inFlight.get(key);
      if (!pending) {
        pending = refresh(caller, boundedFetch, userId, listingId, source, signal);
        inFlight.set(key, pending);
      }
      try {
        await pending;
      } finally {
        if (inFlight.get(key) === pending) inFlight.delete(key);
      }
      if (signal.aborted) {
        throw new SafeError(
          504,
          "refresh_timeout",
          "Walking distance refresh timed out. Try again later.",
        );
      }
      return response(200, { status: "complete" });
    } catch (error) {
      if (signal.aborted) {
        return response(504, {
          code: "refresh_timeout",
          message: "Walking distance refresh timed out. Try again later.",
        });
      }
      if (error instanceof SafeError) {
        return response(error.status, { code: error.code, message: error.message });
      }
      // No raw exception logging: SDK/provider errors may contain JWTs or keys.
      return response(503, {
        code: "refresh_unavailable",
        message: "Walking distances are temporarily unavailable.",
      });
    } finally {
      clearTimeout(timeout);
    }
  };

  async function refresh(
    caller: SupabaseClient,
    boundedFetch: typeof fetch,
    userId: string,
    listingId: string,
    source: Point,
    signal: AbortSignal,
  ): Promise<void> {
    const [universityResult, cacheResult] = await Promise.all([
      caller.from("universities").select("id,latitude,longitude,is_active").eq("is_active", true)
        .order("id").limit(MAX_UNIVERSITIES + 1),
      caller.from("listing_university_routes").select(
        "listing_id,university_id,status,distance_m,calculated_at,listing_latitude,listing_longitude," +
          "university_latitude,university_longitude,routing_version,matched_source_latitude," +
          "matched_source_longitude,matched_target_latitude,matched_target_longitude",
      ).eq("listing_id", listingId).limit(MAX_UNIVERSITIES + 1),
    ]);
    const universities = universitiesFrom(databaseResult(universityResult));
    const cache: unknown = databaseResult(cacheResult);
    if (!Array.isArray(cache)) {
      throw new SafeError(
        503,
        "database_unavailable",
        "Walking distances are temporarily unavailable.",
      );
    }
    // All active pins, not closest-N. The 11km envelope allows both <=100m snaps
    // and spherical-distance error. Only SQL applies the real 10km walking cutoff.
    const missing = universities.filter((university) =>
      greatCircleMeters(source, university) <= CANDIDATE_RADIUS_M &&
      !cache.some((row) => currentRoute(row, listingId, source, university))
    );
    if (missing.length === 0) return;
    const apiKey = config.routingApiKey()?.trim();
    if (!apiKey) {
      throw new SafeError(
        503,
        "routing_not_configured",
        "Walking distance routing is not configured.",
      );
    }

    let provider: Response;
    try {
      provider = await boundedFetch(MATRIX_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-api-key": apiKey },
        body: JSON.stringify({
          mode: "walk",
          type: "short",
          units: "metric",
          sources: [{ location: [source.longitude, source.latitude] }],
          targets: missing.map((university) => ({
            location: [university.longitude, university.latitude],
          })),
        }),
      });
    } catch {
      throw new SafeError(
        502,
        "routing_unavailable",
        "Walking distance routing is temporarily unavailable.",
      );
    }
    if (!provider.ok) await provider.body?.cancel();
    if (provider.status === 429 || provider.status === 402) {
      throw new SafeError(
        429,
        "routing_quota_exceeded",
        "The routing limit has been reached. Try again later.",
      );
    }
    if (provider.status === 401 || provider.status === 403) {
      throw new SafeError(
        503,
        "routing_not_configured",
        "Walking distance routing is not available.",
      );
    }
    if (!provider.ok) {
      throw new SafeError(
        502,
        "routing_unavailable",
        "Walking distance routing is temporarily unavailable.",
      );
    }
    const routes = matrixRoutes(
      await readJson(
        provider.body,
        65_536,
        signal,
        new SafeError(
          502,
          "routing_invalid_response",
          "The routing provider returned unusable data.",
        ),
      ),
      source,
      missing,
    );
    // The privileged client is used ONLY for this RPC, never a table read/write.
    const writer = createClient(config.supabaseUrl, config.serviceRoleKey, {
      global: { fetch: boundedFetch },
      db: { retry: false },
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    });
    const result = await writer.rpc("write_listing_university_routes", {
      p_listing_id: listingId,
      p_landlord_id: userId,
      p_listing_latitude: source.latitude,
      p_listing_longitude: source.longitude,
      p_routing_version: ROUTING_VERSION,
      p_routes: routes,
    });
    if (result.error?.code === "40001") {
      throw new SafeError(
        409,
        "route_snapshot_stale",
        "The property or university pin changed. Reload before retrying.",
      );
    }
    if (result.error?.code === "42501") {
      throw new SafeError(
        403,
        "listing_not_accessible",
        "This property is unavailable to this account.",
      );
    }
    if (
      result.error || !Number.isInteger(result.data) || result.data < 0 ||
      result.data > routes.length
    ) {
      throw new SafeError(
        503,
        "cache_write_failed",
        "The property is saved, but walking distances could not be stored.",
      );
    }
  }
}
