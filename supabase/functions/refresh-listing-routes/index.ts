import { createRefreshHandler } from "./handler.ts";

// Platform-provided keys stay here, never in Flutter. Deploy with Supabase's JWT
// verification enabled; getUser() also verifies the caller inside the handler.
// GEOAPIFY_ROUTING_API_KEY is a private Edge Function secret, NOT the map tile key.
if (import.meta.main) {
  Deno.serve(createRefreshHandler({
    supabaseUrl: Deno.env.get("SUPABASE_URL") ?? "",
    anonKey: Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    serviceRoleKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    routingApiKey: () => Deno.env.get("GEOAPIFY_ROUTING_API_KEY"),
  }));
}
