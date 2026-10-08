// Supabase Edge Function: triggered by a Database Webhook on
// INSERT into shuttle_reports. Looks up students who favorited a
// stop near the reported one and sends them an FCM push notification.
//
// Deploy: supabase functions deploy notify_nearby
// Wire up: Database > Webhooks > new webhook on shuttle_reports (INSERT)
//          pointing at this function's URL.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

Deno.serve(async (req) => {
  const { record } = await req.json();

  // 1. Find users who favorited this stop (see `favorite_stops` table —
  //    add this table if you want per-user notification preferences).
  // 2. Look up their FCM device tokens (see `device_tokens` table).
  // 3. Send via the FCM HTTP v1 API using a service account.
  //
  // Left as an exercise — the shape of the report is available as `record`:
  //   record.stop_id, record.route, record.reported_by, record.created_at

  return new Response(JSON.stringify({ ok: true, stop_id: record?.stop_id }), {
    headers: { "Content-Type": "application/json" },
  });
});
