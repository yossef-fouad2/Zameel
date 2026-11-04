import { GoTrueClient } from "@supabase/supabase-js";
import {
  CANDIDATE_RADIUS_M,
  createRefreshHandler,
  greatCircleMeters,
  type RefreshConfig,
  type RefreshDiagnostic,
  ROUTING_VERSION,
} from "./handler.ts";

const USER = "10000000-0000-4000-8000-000000000001";
const OTHER = "10000000-0000-4000-8000-000000000002";
const LISTING = "20000000-0000-4000-8000-000000000001";
const TOKEN = "test-caller-jwt-not-a-real-credential";
const SECRET = "test-routing-key-not-a-real-credential";
const SERVICE = "test-service-key-not-a-real-credential";
const SOURCE = { latitude: 30.0276, longitude: 31.21014 };
const config: RefreshConfig = {
  supabaseUrl: "https://supabase.test",
  anonKey: "test-anon-key",
  serviceRoleKey: SERVICE,
  routingApiKey: () => SECRET,
};

type Row = Record<string, unknown>;
interface MatrixRequest {
  mode: string;
  type: string;
  units: string;
  sources: { location: [number, number] }[];
  targets: { location: [number, number] }[];
}
interface MatrixResponse {
  sources: { original_location: number[]; location?: number[] | null }[];
  targets: { original_location: number[]; location?: number[] | null }[];
  sources_to_targets: Row[][];
  units: string;
  distance_units: string;
  mode: string;
  type?: string;
}

function assert(value: unknown, label = "assertion failed"): asserts value {
  if (!value) throw new Error(label);
}

function equal(actual: unknown, expected: unknown, label = "values differ") {
  assert(
    JSON.stringify(actual) === JSON.stringify(expected),
    `${label}: ${JSON.stringify(actual)} !== ${JSON.stringify(expected)}`,
  );
}

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function university(id = 1, pin = SOURCE): Row {
  return { id, ...pin, is_active: true };
}

function cacheRow(overrides: Row = {}): Row {
  return {
    listing_id: LISTING,
    university_id: 1,
    status: "ready",
    distance_m: 20,
    calculated_at: "2026-10-21T12:00:00.123456Z",
    listing_latitude: SOURCE.latitude,
    listing_longitude: SOURCE.longitude,
    university_latitude: SOURCE.latitude,
    university_longitude: SOURCE.longitude,
    routing_version: ROUTING_VERSION,
    matched_source_latitude: SOURCE.latitude,
    matched_source_longitude: SOURCE.longitude,
    matched_target_latitude: SOURCE.latitude,
    matched_target_longitude: SOURCE.longitude,
    ...overrides,
  };
}

function matrix(body: MatrixRequest): MatrixResponse {
  return {
    sources: body.sources.map(({ location }) => ({
      original_location: location,
      location: [...location],
    })),
    targets: body.targets.map(({ location }) => ({
      original_location: location,
      location: [...location],
    })),
    sources_to_targets: [body.targets.map((_, target_index) => ({
      distance: 1234.56789,
      time: 1200,
      source_index: 0,
      target_index,
    }))],
    units: "metric",
    distance_units: "meters",
    mode: "walk",
    type: "short",
  };
}

function fixture(
  options: {
    timeoutMs?: number;
    config?: RefreshConfig;
    log?: (diagnostic: RefreshDiagnostic) => void;
  } = {},
) {
  const state = {
    profile: { id: USER, role: "landlord" } as Row | null,
    listing: { id: LISTING, landlord_id: USER, ...SOURCE } as Row | null,
    universities: [university()] as Row[],
    cache: [] as Row[],
    authStatus: 200,
    databaseStatus: 200,
    writerError: null as string | null,
    calls: [] as { url: URL; headers: Headers; body: unknown }[],
    writes: [] as Row[],
    diagnostics: [] as RefreshDiagnostic[],
    intercept: null as ((path: string, signal: AbortSignal) => Promise<Response | null>) | null,
    provider: (body: MatrixRequest, _signal: AbortSignal): Response | Promise<Response> =>
      json(matrix(body)),
  };
  const fetcher: typeof fetch = async (input, init) => {
    const url = new URL(input instanceof Request ? input.url : input.toString());
    const headers = new Headers(init?.headers);
    const body = init?.body ? JSON.parse(String(init.body)) : null;
    state.calls.push({ url, headers, body });
    assert(init?.redirect === "error", "redirects must not forward credentials");
    if (state.intercept) {
      const result = await state.intercept(url.pathname, init!.signal!);
      if (result) return result;
    }
    if (url.origin === "https://api.geoapify.com") {
      equal(url.pathname, "/v1/routematrix");
      equal(url.search, "", "routing key must not appear in URLs");
      equal(headers.get("x-api-key"), SECRET);
      equal(headers.get("authorization"), null, "caller JWT must not reach provider");
      equal(init?.method, "POST");
      return await state.provider(body, init!.signal!);
    }
    equal(url.origin, config.supabaseUrl, "no unexpected/live transport");
    if (url.pathname === "/rest/v1/rpc/write_listing_university_routes") {
      equal(headers.get("authorization"), `Bearer ${SERVICE}`);
      equal(headers.get("apikey"), SERVICE);
      equal(headers.get("content-profile"), "public");
      equal(headers.get("content-type"), "application/json");
      equal(init?.method, "POST");
      state.writes.push(body);
      if (state.writerError) {
        return json({ code: state.writerError, message: `private ${SECRET}` }, 409);
      }
      let changed = 0;
      for (const route of body.p_routes) {
        const target = state.universities.find((row) => row.id === route.university_id);
        if (
          state.listing?.latitude !== body.p_listing_latitude ||
          state.listing?.longitude !== body.p_listing_longitude ||
          target?.latitude !== route.university_latitude ||
          target?.longitude !== route.university_longitude
        ) {
          return json({ code: "PT409", message: "route_snapshot_stale" }, 409);
        }
        const existing = state.cache.findIndex((row) => row.university_id === route.university_id);
        const next = cacheRow({
          ...route,
          listing_latitude: body.p_listing_latitude,
          listing_longitude: body.p_listing_longitude,
        });
        if (existing < 0) state.cache.push(next);
        else state.cache[existing] = next;
        changed++;
      }
      return json(changed);
    }
    // Every table read and getUser must use the caller, NEVER service_role.
    equal(headers.get("authorization"), `Bearer ${TOKEN}`);
    equal(headers.get("apikey"), config.anonKey);
    if (url.pathname === "/auth/v1/user") {
      if (state.authStatus === 0) throw new Error(`${TOKEN} https://private.test`);
      return state.authStatus === 200
        ? json({
          id: USER,
          aud: "authenticated",
          role: "authenticated",
          user_metadata: { role: "landlord" },
        })
        : json({ message: `private ${TOKEN}`, code: "bad_jwt" }, state.authStatus);
    }
    if (state.databaseStatus === 0) throw new Error(`${SERVICE} https://private.test`);
    if (state.databaseStatus !== 200) {
      return json({ code: "42501", message: SECRET }, state.databaseStatus);
    }
    if (url.pathname === "/rest/v1/profiles") {
      equal(url.searchParams.get("id"), `eq.${USER}`);
      return json(state.profile ? [state.profile] : []);
    }
    if (url.pathname === "/rest/v1/listings") {
      equal(url.searchParams.get("id"), `eq.${LISTING}`);
      equal(
        url.searchParams.get("landlord_id"),
        `eq.${USER}`,
        "explicit owner filter required for public listings",
      );
      return json(state.listing ? [state.listing] : []);
    }
    if (url.pathname === "/rest/v1/universities") {
      equal(url.searchParams.get("is_active"), "eq.true");
      equal(
        url.searchParams.get("limit"),
        "17",
        "fail closed on an unexpectedly expanded catalogue",
      );
      return json(state.universities);
    }
    if (url.pathname === "/rest/v1/listing_university_routes") {
      equal(url.searchParams.get("listing_id"), `eq.${LISTING}`);
      return json(state.cache);
    }
    throw new Error(`Unexpected test endpoint ${url.pathname}`);
  };
  const handler = createRefreshHandler(options.config ?? config, {
    fetch: fetcher,
    timeoutMs: options.timeoutMs,
    log: options.log ?? ((diagnostic) => state.diagnostics.push(structuredClone(diagnostic))),
  });
  return {
    state,
    handler,
    run: () => handler(request()),
    providerCalls: () =>
      state.calls.filter((call) => call.url.origin === "https://api.geoapify.com"),
  };
}

function request(body: unknown = { listing_id: LISTING }, headers: Record<string, string> = {}) {
  return new Request("https://edge.test/refresh-listing-routes", {
    method: "POST",
    headers: { Authorization: `Bearer ${TOKEN}`, "Content-Type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
}

async function failure(result: Response, status: number, code: string) {
  equal(result.status, status);
  const body = await result.json();
  equal(body.code, code);
  equal(
    Object.keys(body).sort(),
    code === "refresh_timeout" ? ["code", "message", "request_id", "stage"] : ["code", "message"],
  );
  if (code === "refresh_timeout") {
    assert(typeof body.request_id === "string" && /^[a-f0-9-]{36}$/.test(body.request_id));
    assert([
      "request",
      "authentication",
      "profile",
      "listing",
      "route_cache",
      "geoapify",
      "cache_write",
      "shared_refresh",
    ].includes(body.stage));
  }
  assert(typeof body.message === "string" && body.message.length > 0);
  for (const privateValue of [TOKEN, SECRET, SERVICE, "https://"]) {
    assert(
      !JSON.stringify(body).includes(privateValue),
      "failure must not disclose credentials/raw URLs",
    );
  }
}

Deno.test("owner identity, persisted role and owner filter precede one metric shortest-walk matrix", async () => {
  const f = fixture();
  const result = await f.run();
  equal(result.status, 200);
  equal(await result.json(), { status: "complete" });
  equal(f.state.calls.map((call) => call.url.pathname), [
    "/auth/v1/user",
    "/rest/v1/profiles",
    "/rest/v1/listings",
    "/rest/v1/universities",
    "/rest/v1/listing_university_routes",
    "/v1/routematrix",
    "/rest/v1/rpc/write_listing_university_routes",
  ]);
  equal(f.providerCalls()[0].body, {
    mode: "walk",
    type: "short",
    units: "metric",
    sources: [{ location: [SOURCE.longitude, SOURCE.latitude] }],
    targets: [{ location: [SOURCE.longitude, SOURCE.latitude] }],
  });
  equal(f.state.writes[0].p_listing_id, LISTING);
  equal(f.state.writes[0].p_landlord_id, USER);
  equal(f.state.writes[0].p_routing_version, ROUTING_VERSION);
  equal((f.state.writes[0].p_routes as Row[])[0].distance_m, 1234.56789);
  await f.run();
  equal(f.providerCalls().length, 1, "repeat refresh must reuse saved cache");
});

Deno.test("anonymous, invalid JWT, missing/forged role and other-owner requests cannot spend quota", async () => {
  const anonymous = fixture();
  await failure(
    await anonymous.handler(request(undefined, { Authorization: "" })),
    401,
    "unauthorized",
  );
  equal(anonymous.state.calls.length, 0);
  for (const scenario of ["jwt", "student", "missing_profile", "owner", "missing_listing"]) {
    const f = fixture();
    if (scenario === "jwt") f.state.authStatus = 401;
    if (scenario === "student") f.state.profile!.role = "student"; // Auth metadata still says landlord.
    if (scenario === "missing_profile") f.state.profile = null;
    if (scenario === "owner") f.state.listing!.landlord_id = OTHER;
    if (scenario === "missing_listing") f.state.listing = null;
    await failure(
      await f.run(),
      scenario === "jwt" ? 401 : scenario.includes("profile") || scenario === "student" ? 403 : 404,
      scenario === "jwt"
        ? "unauthorized"
        : scenario.includes("profile") || scenario === "student"
        ? "landlord_role_required"
        : "listing_not_accessible",
    );
    equal(f.providerCalls().length, 0);
    equal(f.state.writes.length, 0);
  }
});

Deno.test("only a small JSON listing_id request is accepted; CORS does not authenticate", async () => {
  for (
    const body of [
      null,
      [],
      {},
      { listing_id: "not-uuid" },
      { listing_id: LISTING, distance_m: 0 },
      { listing_id: "x".repeat(2000) },
    ]
  ) {
    const f = fixture();
    await failure(await f.handler(request(body)), 400, "invalid_request");
    equal(f.state.calls.length, 0);
  }
  const f = fixture();
  await failure(
    await f.handler(request(undefined, { "Content-Type": "text/plain" })),
    415,
    "invalid_request",
  );
  await failure(
    await f.handler(new Request("https://edge.test", { method: "GET" })),
    405,
    "method_not_allowed",
  );
  const options = await f.handler(new Request("https://edge.test", { method: "OPTIONS" }));
  equal(options.status, 204);
  equal(options.headers.get("access-control-allow-origin"), "*");
  equal(f.state.calls.length, 0);
});

Deno.test("missing/out-of-range/non-number property pins fail before routing", async () => {
  for (
    const pin of [
      { latitude: null, longitude: null },
      { latitude: 30, longitude: null },
      { latitude: 91, longitude: 30 },
      { latitude: 30, longitude: -181 },
      { latitude: Number.NaN, longitude: 30 },
      { latitude: 30, longitude: Infinity },
      { latitude: "30", longitude: 30 },
    ]
  ) {
    const f = fixture();
    Object.assign(f.state.listing!, pin);
    await failure(await f.run(), 409, "listing_pin_required");
    equal(f.providerCalls().length, 0);
  }
});

Deno.test("all 16 pins are considered, never closest-N; only the conservative 11km envelope filters", async () => {
  const f = fixture();
  f.state.universities = Array.from(
    { length: 16 },
    (_, index) =>
      university(index + 1, {
        latitude: SOURCE.latitude,
        longitude: SOURCE.longitude + index / 1000,
      }),
  );
  await f.run();
  equal((f.providerCalls()[0].body as MatrixRequest).targets.length, 16);
  equal(
    (f.state.writes[0].p_routes as Row[]).map((row) => row.university_id),
    Array.from({ length: 16 }, (_, i) => i + 1),
  );

  const boundary = fixture();
  boundary.state.listing = { id: LISTING, landlord_id: USER, latitude: 0, longitude: 0 };
  const latitudeForMeters = (meters: number) => meters / 6_371_008.8 * 180 / Math.PI;
  boundary.state.universities = [
    university(1, { latitude: latitudeForMeters(10_999.9), longitude: 0 }),
    university(2, { latitude: latitudeForMeters(11_000.1), longitude: 0 }),
  ];
  await boundary.run();
  equal((boundary.state.writes[0].p_routes as Row[]).map((row) => row.university_id), [1]);
  equal(CANDIDATE_RADIUS_M, 11_000);
  equal(greatCircleMeters(SOURCE, SOURCE), 0);
  assert(
    greatCircleMeters({ latitude: 0, longitude: 0 }, { latitude: 0, longitude: 180 }) > 20_000_000,
  );
});

Deno.test("invalid or unexpectedly expanded catalogue fails closed before quota use", async () => {
  for (
    const rows of [
      [university(), university()],
      [university(1, { latitude: 90.1, longitude: 31 })],
      [university(1.5)],
      [{ ...university(), is_active: false }],
      Array.from({ length: 17 }, (_, i) => university(i + 1)),
    ]
  ) {
    const f = fixture();
    f.state.universities = rows;
    await failure(await f.run(), 503, "catalogue_invalid");
    equal(f.providerCalls().length, 0);
  }
});

Deno.test("empty/distant catalogue and all cached outcomes need no provider secret or writes", async () => {
  for (
    const outcome of ["empty", "distant", "ready", "unroutable", "needs_pin_review", "over_limit"]
  ) {
    const f = fixture({
      config: {
        ...config,
        routingApiKey: () => {
          throw new Error("must not read routing secret");
        },
      },
    });
    if (outcome === "empty") f.state.universities = [];
    else if (outcome === "distant") {
      f.state.universities = [university(4, { latitude: 31.20194, longitude: 29.90528 })];
    } else {f.state.cache = [cacheRow({
        status: outcome === "over_limit" ? "ready" : outcome,
        distance_m: outcome === "ready" ? 0 : outcome === "over_limit" ? 12_000 : null,
        ...(outcome === "needs_pin_review"
          ? { matched_source_latitude: SOURCE.latitude + 0.01 }
          : {}),
      })];}
    const result = await f.run();
    equal(result.status, 200);
    equal(await result.json(), { status: "complete" });
    equal(f.providerCalls().length, 0);
    equal(f.state.writes.length, 0);
  }
});

Deno.test("stale endpoint snapshots/version and invalid cache rows are never reused", async () => {
  for (
    const change of [
      { listing_latitude: SOURCE.latitude + 0.01 },
      { listing_longitude: SOURCE.longitude + 0.01 },
      { university_latitude: SOURCE.latitude + 0.01 },
      { university_longitude: SOURCE.longitude + 0.01 },
      { routing_version: "old" },
      { distance_m: null },
      { distance_m: -1 },
      { matched_source_latitude: SOURCE.latitude + 0.01 },
      { calculated_at: "invalid" },
    ]
  ) {
    const f = fixture();
    f.state.cache = [cacheRow(change)];
    equal((await f.run()).status, 200);
    equal(f.providerCalls().length, 1);
  }
});

Deno.test("cache missing pairs only, including unreachable/over-10km outcomes without rounding", async () => {
  const f = fixture();
  f.state.universities = [university(1), university(2), university(3), university(4)];
  f.state.cache = [cacheRow()];
  f.state.provider = (body) => {
    const value = matrix(body);
    equal(body.targets.length, 3);
    value.sources_to_targets[0][0].distance = 0;
    value.sources_to_targets[0][1].distance = null;
    value.sources_to_targets[0][1].time = null;
    delete value.targets[1].location;
    value.sources_to_targets[0][2].distance = 10_000.000001;
    return json(value);
  };
  equal((await f.run()).status, 200);
  equal(
    (f.state.writes[0].p_routes as Row[]).map((
      row,
    ) => [row.university_id, row.status, row.distance_m]),
    [
      [2, "ready", 0],
      [3, "unroutable", null],
      [4, "ready", 10_000.000001],
    ],
  );
  equal(f.state.cache[0], cacheRow(), "previous valid cache must remain unchanged");
});

Deno.test("either null metric means unreachable, never an invented zero distance", async () => {
  for (
    const cell of [{ distance: null, time: 0 }, { distance: 0, time: null }, {
      distance: null,
      time: null,
    }]
  ) {
    const f = fixture();
    f.state.provider = (body) => {
      const value = matrix(body);
      Object.assign(value.sources_to_targets[0][0], cell);
      return json(value);
    };
    equal((await f.run()).status, 200);
    equal((f.state.writes[0].p_routes as Row[])[0].status, "unroutable");
    equal((f.state.writes[0].p_routes as Row[])[0].distance_m, null);
  }
});

Deno.test("source or target snapping beyond 100m is cached as needs_pin_review", async () => {
  for (const endpoint of ["sources", "targets"] as const) {
    for (const meters of [99.9, 100.1]) {
      const f = fixture();
      f.state.provider = (body) => {
        const value = matrix(body);
        value[endpoint][0].location![1] += meters / 6_371_008.8 * 180 / Math.PI;
        return json(value);
      };
      equal((await f.run()).status, 200);
      const row = (f.state.writes[0].p_routes as Row[])[0];
      equal(row.status, meters > 100 ? "needs_pin_review" : "ready");
      equal(row.distance_m, meters > 100 ? null : 1234.56789);
    }
  }
});

Deno.test("malformed/wrong/missing matrix cells and endpoint metadata fail the entire response", async () => {
  const invalidCases: ((value: MatrixResponse) => void)[] = [
    (v) => {
      v.sources_to_targets = [];
    },
    (v) => {
      v.sources_to_targets[0] = [];
    },
    (v) => {
      v.sources_to_targets[0].push(v.sources_to_targets[0][0]);
    },
    (v) => {
      v.sources_to_targets[0][0].source_index = 1;
    },
    (v) => {
      v.sources_to_targets[0][0].target_index = 1;
    },
    (v) => {
      delete v.sources_to_targets[0][0].distance;
    },
    (v) => {
      delete v.sources_to_targets[0][0].time;
    },
    (v) => {
      v.sources_to_targets[0][0].distance = -1;
    },
    (v) => {
      v.sources_to_targets[0][0].distance = "10";
    },
    (v) => {
      v.sources_to_targets[0][0].time = -1;
    },
    (v) => {
      v.sources = [];
    },
    (v) => {
      v.targets = [];
    },
    (v) => {
      v.sources[0].original_location = [SOURCE.latitude, SOURCE.longitude];
    },
    (v) => {
      v.targets[0].original_location = [SOURCE.longitude + 0.001, SOURCE.latitude];
    },
    (v) => {
      v.targets[0].location = [181, 30];
    },
    (v) => {
      delete v.sources[0].location;
    },
    (v) => {
      v.targets[0].location = null;
    },
    (v) => {
      v.units = "imperial";
    },
    (v) => {
      v.distance_units = "miles";
    },
    (v) => {
      v.mode = "drive";
    },
    (v) => {
      v.type = "balanced";
    },
  ];
  for (const corrupt of invalidCases) {
    const f = fixture();
    f.state.provider = (body) => {
      const value = matrix(body);
      corrupt(value);
      return json(value);
    };
    await failure(await f.run(), 502, "routing_invalid_response");
    equal(f.state.writes.length, 0);
  }
  for (const malformed of ["not json", "x".repeat(65_537), "[null]"]) {
    const f = fixture();
    f.state.provider = () => new Response(malformed);
    await failure(await f.run(), 502, "routing_invalid_response");
  }
  const nonFinite = fixture();
  nonFinite.state.provider = (body) =>
    new Response(JSON.stringify(matrix(body)).replace("1234.56789", "1e999"));
  await failure(await nonFinite.run(), 502, "routing_invalid_response");
  equal(nonFinite.state.writes.length, 0);
});

Deno.test("quota/provider/network errors are safe, never retry or destroy an existing valid row", async () => {
  for (const status of [429, 402, 401, 403, 500, 400, 0]) {
    const f = fixture();
    f.state.universities = [university(1), university(2)];
    f.state.cache = [cacheRow()];
    f.state.provider = () => {
      if (status === 0) throw new Error(`${SECRET} ${TOKEN} https://private.test`);
      return json({ message: `${SECRET} ${TOKEN} https://private.test` }, status);
    };
    await failure(
      await f.run(),
      status === 429 || status === 402 ? 429 : status === 401 || status === 403 ? 503 : 502,
      status === 429 || status === 402
        ? "routing_quota_exceeded"
        : status === 401 || status === 403
        ? "routing_not_configured"
        : "routing_unavailable",
    );
    equal(f.providerCalls().length, 1);
    equal(f.state.writes.length, 0);
    equal(f.state.cache, [cacheRow()]);
  }
});

Deno.test("provider timeout aborts with no retry, write or fake success", async () => {
  const f = fixture({ timeoutMs: 50 });
  f.state.provider = (_body, signal) =>
    new Promise((_resolve, reject) => {
      signal.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError")), {
        once: true,
      });
    });
  await failure(await f.run(), 504, "refresh_timeout");
  equal(f.providerCalls().length, 1);
  equal(f.state.writes.length, 0);
  assert(Number.isFinite(f.state.diagnostics[0].timings_ms.geoapify));
});

Deno.test("deadline returns even when transport ignores abort and prevents late writes", async () => {
  const f = fixture({ timeoutMs: 50 });
  const entered = Promise.withResolvers<MatrixRequest>();
  const provider = Promise.withResolvers<Response>();
  f.state.provider = (body) => {
    entered.resolve(body);
    return provider.promise;
  };
  const pending = f.run();
  const body = await entered.promise;
  let guard: ReturnType<typeof setTimeout> | undefined;
  try {
    const result = await Promise.race([
      pending,
      new Promise<null>((resolve) => guard = setTimeout(() => resolve(null), 200)),
    ]);
    assert(result !== null, "aborting fetch alone must not leave the handler waiting forever");
    await failure(result, 504, "refresh_timeout");
    equal(f.state.writes.length, 0);
  } finally {
    if (guard !== undefined) clearTimeout(guard);
    provider.resolve(json(matrix(body)));
    await pending;
  }
  equal(f.state.writes.length, 0, "late provider completion must not dispatch a cache write");
});

Deno.test("coalesced callers receive the same classified timeout and can retry", async () => {
  const f = fixture({ timeoutMs: 100 });
  const entered = Promise.withResolvers<void>();
  f.state.provider = (_body, signal) => {
    entered.resolve();
    return new Promise((_resolve, reject) => {
      signal.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError")), {
        once: true,
      });
    });
  };
  const leader = f.run();
  await entered.promise;
  await new Promise((resolve) => setTimeout(resolve, 20));
  const follower = f.run();
  const results = await Promise.all([leader, follower]);
  for (const result of results) await failure(result, 504, "refresh_timeout");
  equal(f.providerCalls().length, 1);
  equal(f.state.writes.length, 0);
  f.state.provider = (body) => json(matrix(body));
  equal((await f.run()).status, 200, "a completed timeout must not poison later refreshes");
  equal(f.providerCalls().length, 2);
  equal(f.state.writes.length, 1);
});

for (
  const [path, stage] of [
    ["/auth/v1/user", "authentication"],
    ["/rest/v1/profiles", "profile"],
    ["/rest/v1/listings", "listing"],
    ["/rest/v1/universities", "route_cache"],
    ["/rest/v1/listing_university_routes", "route_cache"],
    ["/rest/v1/rpc/write_listing_university_routes", "cache_write"],
  ] as const
) {
  Deno.test(`deadline bounds stalled ${path} headers/bodies and names the stage safely`, async () => {
    for (const stalled of ["headers", "body"]) {
      const f = fixture({ timeoutMs: 50 });
      const entered = Promise.withResolvers<AbortSignal>();
      const headers = Promise.withResolvers<Response | null>();
      let body: ReadableStreamDefaultController<Uint8Array> | undefined;
      let bodyCancelled = false;
      f.state.intercept = (requestPath, signal) => {
        if (requestPath !== path) return Promise.resolve(null);
        entered.resolve(signal);
        if (stalled === "headers") return headers.promise;
        return Promise.resolve(
          new Response(
            new ReadableStream<Uint8Array>({
              start(controller) {
                body = controller;
                controller.enqueue(new TextEncoder().encode("{"));
              },
              cancel() {
                bodyCancelled = true;
              },
            }),
          ),
        );
      };
      const pending = f.run();
      const signal = await entered.promise;
      let guard: ReturnType<typeof setTimeout> | undefined;
      let dispatched = 0;
      try {
        const result = await Promise.race([
          pending,
          new Promise<never>((_resolve, reject) => {
            guard = setTimeout(() => reject(new Error(`${stage} exceeded its deadline`)), 250);
          }),
        ]);
        const details = await result.clone().json();
        await failure(result, 504, "refresh_timeout");
        equal(details.stage, stage);
        assert(signal.aborted, "timeout must also cancel the underlying transport");
        const diagnostic = f.state.diagnostics.at(-1)!;
        equal(diagnostic.request_id, details.request_id);
        equal(diagnostic.stage, stage);
        equal(diagnostic.status, 504);
        equal(diagnostic.code, "refresh_timeout");
        assert(Number.isFinite(diagnostic.timings_ms[stage]));
        dispatched = f.state.calls.length;
      } finally {
        if (guard !== undefined) clearTimeout(guard);
        headers.resolve(null);
        if (!bodyCancelled) body?.close();
        await pending;
        await new Promise((resolve) => setTimeout(resolve, 0));
      }
      equal(
        f.state.calls.length,
        dispatched,
        "late SDK work must not dispatch subsequent requests",
      );
      if (stage !== "cache_write") equal(f.providerCalls().length, 0);
      if (stage === "cache_write" && stalled === "body") {
        assert(bodyCancelled, "the RPC response body must be cancelled at the deadline");
      }
      for (const secret of [TOKEN, SECRET, SERVICE, USER, LISTING, "https://"]) {
        assert(
          !JSON.stringify(f.state.diagnostics).includes(secret),
          "diagnostics must be redacted",
        );
      }
    }
  });
}

Deno.test("a waiter's deadline neither waits for nor evicts another caller's live refresh", async () => {
  const f = fixture({ timeoutMs: 500 });
  const authEntered = Promise.withResolvers<void>();
  const authRelease = Promise.withResolvers<void>();
  const routingEntered = Promise.withResolvers<MatrixRequest>();
  const routingRelease = Promise.withResolvers<Response>();
  let authCalls = 0;
  f.state.intercept = async (path) => {
    if (path === "/auth/v1/user" && ++authCalls === 1) {
      authEntered.resolve();
      await authRelease.promise;
    }
    return null;
  };
  f.state.provider = (body) => {
    routingEntered.resolve(body);
    return routingRelease.promise;
  };
  const earlier = f.run();
  await authEntered.promise;
  await new Promise((resolve) => setTimeout(resolve, 200));
  let leaderFinished = false;
  const leader = f.run().then((value) => {
    leaderFinished = true;
    return value;
  });
  const matrixBody = await routingEntered.promise;
  authRelease.resolve();
  let follower: Promise<Response> | undefined;
  try {
    const result = await earlier;
    equal((await result.clone().json()).stage, "shared_refresh");
    await failure(result, 504, "refresh_timeout");
    assert(!leaderFinished, "an older waiter must respect its own deadline");
    follower = f.run();
    await new Promise((resolve) => setTimeout(resolve, 0));
    equal(f.providerCalls().length, 1, "a waiter must not remove the leader's in-flight entry");
  } finally {
    routingRelease.resolve(json(matrix(matrixBody)));
    await Promise.all([earlier, leader, follower]);
  }
  equal((await leader).status, 200);
  equal((await follower!).status, 200);
  equal(f.providerCalls().length, 1);
  equal(f.state.writes.length, 1);
});

Deno.test("a lost cache-write response is reconciled by the next refresh without routing again", async () => {
  const f = fixture({ timeoutMs: 50 });
  let body: ReadableStreamDefaultController<Uint8Array> | undefined;
  let bodyCancelled = false;
  f.state.intercept = (path) => {
    if (path !== "/rest/v1/rpc/write_listing_university_routes") return Promise.resolve(null);
    const write = f.state.calls.at(-1)!.body as Row;
    f.state.writes.push(write);
    const routes = write.p_routes as Row[];
    f.state.cache.push(cacheRow(routes[0]));
    return Promise.resolve(
      new Response(
        new ReadableStream<Uint8Array>({
          start(controller) {
            body = controller;
            controller.enqueue(new TextEncoder().encode("1"));
          },
          cancel() {
            bodyCancelled = true;
          },
        }),
      ),
    );
  };
  try {
    const result = await f.run();
    equal((await result.clone().json()).stage, "cache_write");
    await failure(result, 504, "refresh_timeout");
  } finally {
    if (!bodyCancelled) body?.close();
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
  f.state.intercept = null;
  equal((await f.run()).status, 200);
  equal(f.providerCalls().length, 1);
  equal(f.state.writes.length, 1);
  equal(f.state.cache[0].distance_m, 1234.56789);
});

Deno.test("the static service-role RPC never waits for an Auth session", async () => {
  const original = GoTrueClient.prototype.getSession;
  const stalled = Promise.withResolvers<Awaited<ReturnType<typeof original>>>();
  let serviceSessionReads = 0;
  GoTrueClient.prototype.getSession = function () {
    const headers = Reflect.get(this, "headers") as Record<string, string>;
    if (headers.apikey === SERVICE) {
      serviceSessionReads++;
      return stalled.promise;
    }
    return original.call(this);
  };
  const f = fixture({ timeoutMs: 50 });
  try {
    const result = await f.run();
    equal(
      result.status,
      200,
      "cache_write must dispatch using the server credential, not wait on getSession()",
    );
    equal(await result.json(), { status: "complete" });
    equal(serviceSessionReads, 0);
    equal(f.state.writes.length, 1);
    equal(f.providerCalls().length, 1);
  } finally {
    GoTrueClient.prototype.getSession = original;
    stalled.resolve({ data: { session: null }, error: null });
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
});

Deno.test("the direct RPC accepts only bounded successful integer counts", async () => {
  const responses = [
    () => json(null),
    () => json("1"),
    () => json([1]),
    () => json({ count: 1 }),
    () => json(-1),
    () => json(1.5),
    () => json(2),
    () => json(1, 500),
    () => new Response(null, { status: 204 }),
    () => new Response(`<html>private ${SECRET}</html>`, { status: 502 }),
    () => new Response(JSON.stringify({ message: SECRET.repeat(1_000) }), { status: 503 }),
  ];
  for (const respond of responses) {
    const f = fixture();
    f.state.intercept = (path) =>
      Promise.resolve(
        path === "/rest/v1/rpc/write_listing_university_routes" ? respond() : null,
      );
    await failure(await f.run(), 503, "cache_write_failed");
    equal(f.providerCalls().length, 1);
    equal(f.state.calls.filter((call) => call.url.pathname.includes("/rpc/")).length, 1);
    equal(f.state.cache.length, 0);
    assert(!JSON.stringify(f.state.diagnostics).includes(SECRET));
  }
  for (const count of [0, 1]) {
    const f = fixture();
    f.state.intercept = (path) =>
      Promise.resolve(
        path === "/rest/v1/rpc/write_listing_university_routes" ? json(count) : null,
      );
    equal((await f.run()).status, 200);
  }
  for (const bytes of [16_384, 16_385]) {
    const f = fixture({ timeoutMs: 500 });
    let cancelled = false;
    f.state.intercept = (path) => {
      if (path !== "/rest/v1/rpc/write_listing_university_routes") return Promise.resolve(null);
      return Promise.resolve(
        new Response(
          new ReadableStream<Uint8Array>({
            start(controller) {
              controller.enqueue(new TextEncoder().encode(`1${" ".repeat(bytes - 1)}`));
              if (bytes === 16_384) controller.close();
            },
            cancel() {
              cancelled = true;
            },
          }),
        ),
      );
    };
    const result = await f.run();
    if (bytes === 16_384) equal(result.status, 200);
    else {
      await failure(result, 503, "cache_write_failed");
      assert(cancelled, "oversized successful RPC bodies must be cancelled, not parsed as success");
    }
  }
});

Deno.test("a direct RPC transport failure is redacted and never automatically retried", async () => {
  const f = fixture();
  f.state.intercept = (path) => {
    if (path === "/rest/v1/rpc/write_listing_university_routes") {
      throw new Error(`private transport ${SERVICE} ${TOKEN}`);
    }
    return Promise.resolve(null);
  };
  await failure(await f.run(), 503, "cache_write_failed");
  equal(f.providerCalls().length, 1);
  equal(f.state.calls.filter((call) => call.url.pathname.includes("/rpc/")).length, 1);
  equal(f.state.cache.length, 0);
  for (const secret of [SERVICE, TOKEN]) {
    assert(!JSON.stringify(f.state.diagnostics).includes(secret));
  }
});

Deno.test("success diagnostics contain only request IDs, stage names, status and timings", async () => {
  const f = fixture();
  equal((await f.run()).status, 200);
  equal(f.state.diagnostics.length, 1);
  const diagnostic = f.state.diagnostics[0];
  equal(diagnostic.event, "listing_routes_refresh");
  equal(diagnostic.stage, "cache_write");
  equal(diagnostic.status, 200);
  equal(diagnostic.code, "complete");
  assert(diagnostic.elapsed_ms >= 0);
  equal(Object.keys(diagnostic.timings_ms), [
    "request",
    "authentication",
    "profile",
    "listing",
    "route_cache",
    "geoapify",
    "cache_write",
  ]);
  for (const secret of [TOKEN, SECRET, SERVICE, USER, LISTING, "https://"]) {
    assert(!JSON.stringify(diagnostic).includes(secret));
  }
});

Deno.test("diagnostic sink failure cannot replace a success or a classified timeout", async () => {
  for (const timeout of [false, true]) {
    const f = fixture({
      timeoutMs: 50,
      log: () => {
        throw new Error(`sink failed ${TOKEN} ${SECRET}`);
      },
    });
    if (timeout) {
      f.state.provider = (_body, signal) =>
        new Promise((_resolve, reject) => {
          signal.addEventListener("abort", () => reject(signal.reason), { once: true });
        });
    }
    const result = await f.run();
    if (timeout) await failure(result, 504, "refresh_timeout");
    else {
      equal(result.status, 200);
      equal(await result.json(), { status: "complete" });
    }
  }
});

Deno.test("configuration, database, and writer failures are distinct from successful completion", async () => {
  const missingKey = fixture({ config: { ...config, routingApiKey: () => undefined } });
  await failure(await missingKey.run(), 503, "routing_not_configured");
  equal(missingKey.providerCalls().length, 0);
  const missingConfig = fixture({ config: { ...config, serviceRoleKey: "" } });
  await failure(await missingConfig.run(), 503, "service_not_configured");
  equal(missingConfig.state.calls.length, 0);
  const database = fixture();
  database.state.databaseStatus = 500;
  await failure(await database.run(), 503, "database_unavailable");
  equal(database.providerCalls().length, 0);
  for (const code of ["PT409", "40001", "42501", "22023", "55P03"]) {
    const f = fixture();
    f.state.writerError = code;
    await failure(
      await f.run(),
      code === "PT409" || code === "40001" ? 409 : code === "42501" ? 403 : 503,
      code === "PT409" || code === "40001"
        ? "route_snapshot_stale"
        : code === "42501"
        ? "listing_not_accessible"
        : "cache_write_failed",
    );
    equal(f.state.writes.length, 1);
    equal(f.providerCalls().length, 1);
  }
});

Deno.test("provider completion sends the ORIGINAL DB snapshots, so a concurrent pin edit is rejected", async () => {
  for (const endpoint of ["listing", "university"]) {
    const f = fixture();
    f.state.provider = (body) => {
      if (endpoint === "listing") f.state.listing!.latitude = SOURCE.latitude + 0.1;
      else f.state.universities[0].latitude = SOURCE.latitude + 0.1;
      return json(matrix(body));
    };
    await failure(await f.run(), 409, "route_snapshot_stale");
    equal(f.state.writes[0].p_listing_latitude, SOURCE.latitude);
    equal((f.state.writes[0].p_routes as Row[])[0].university_latitude, SOURCE.latitude);
    equal(f.state.cache.length, 0);
  }
});

Deno.test("simultaneous same-isolate same-pin refreshes coalesce into one provider call/write", async () => {
  const f = fixture();
  const results = await Promise.all([f.run(), f.run(), f.run()]);
  for (const result of results) equal(result.status, 200);
  equal(f.providerCalls().length, 1);
  equal(f.state.writes.length, 1);
});

Deno.test("SDK transient Auth/PostgREST failures do not introduce hidden retry loops or raw logging", async () => {
  const logged: unknown[][] = [];
  const original = { log: console.log, warn: console.warn, error: console.error };
  console.log = console.warn = console.error = (...args: unknown[]) => {
    logged.push(args);
  };
  try {
    for (const layer of ["auth", "database"]) {
      for (const status of [0, 503, 520]) {
        const f = fixture({ timeoutMs: 1000 });
        if (layer === "auth") f.state.authStatus = status;
        else f.state.databaseStatus = status;
        await failure(
          await f.run(),
          503,
          layer === "auth" ? "authentication_unavailable" : "database_unavailable",
        );
        equal(f.state.calls.filter((call) => call.url.pathname === "/auth/v1/user").length, 1);
        equal(
          f.state.calls.filter((call) => call.url.pathname === "/rest/v1/profiles").length,
          layer === "auth" ? 0 : 1,
        );
        equal(f.providerCalls().length, 0);
      }
    }
  } finally {
    Object.assign(console, original);
  }
  equal(logged, [], "raw SDK transport errors must not be logged");
});

Deno.test("timeout covers unfinished request and provider bodies, not just response headers", async () => {
  for (const layer of ["request", "provider"]) {
    const f = fixture({ timeoutMs: 50 });
    let cancelled = false;
    const stalled = new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(new TextEncoder().encode("{"));
      },
      cancel() {
        cancelled = true;
      },
    });
    if (layer === "provider") f.state.provider = () => new Response(stalled);
    const result = layer === "provider" ? await f.run() : await f.handler(
      new Request("https://edge.test", {
        method: "POST",
        headers: { Authorization: `Bearer ${TOKEN}`, "Content-Type": "application/json" },
        body: stalled,
      }),
    );
    await failure(result, 504, "refresh_timeout");
    assert(cancelled, "deadline must cancel the unfinished body");
    equal(f.providerCalls().length, layer === "provider" ? 1 : 0);
    equal(f.state.writes.length, 0);
  }
});
