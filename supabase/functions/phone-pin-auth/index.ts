import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { phone, pin } = await req.json();
    if (!phone || !pin) {
      return new Response(
        JSON.stringify({ error: "Phone and PIN are required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const cleanPhone = phone.replace(/\D/g, "");
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    // 1. Verify PIN hash in PostgreSQL
    const { data: verifyData, error: verifyErr } = await supabaseAdmin.rpc(
      "verify_user_custom_pin_by_phone",
      { p_phone: cleanPhone, p_pin: pin.trim() }
    );

    if (verifyErr || !verifyData?.success) {
      return new Response(
        JSON.stringify({ error: verifyData?.error ?? "Authentication failed" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const userId = verifyData.user_id;
    const internalEmail = `${cleanPhone}@phone.internal`;
    const internalPassword = `MetroShift@${cleanPhone}!2026`;

    // 2. Ensure the user exists in auth.users
    const { data: userData, error: getUserErr } = await supabaseAdmin.auth.admin.getUserById(userId);

    if (getUserErr || !userData?.user) {
      // Create user with explicit ID to match profiles.id
      const { error: createErr } = await supabaseAdmin.auth.admin.createUser({
        id: userId,
        email: internalEmail,
        password: internalPassword,
        email_confirm: true,
        user_metadata: {
          role: verifyData.role,
          full_name: verifyData.full_name,
        },
      });

      if (createErr && !createErr.message.includes("already been registered")) {
        throw createErr;
      }
    } else {
      // Sync credentials so password remains valid
      await supabaseAdmin.auth.admin.updateUserById(userId, {
        password: internalPassword,
        email: internalEmail,
      });
    }

    // 3. Authenticate with GoTrue to officially create a session in auth.sessions
    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const { data: sessionData, error: signInErr } = await userClient.auth.signInWithPassword({
      email: internalEmail,
      password: internalPassword,
    });

    if (signInErr || !sessionData?.session) {
      throw signInErr ?? new Error("Failed to register session");
    }

    // Return official GoTrue tokens
    return new Response(
      JSON.stringify({
        access_token: sessionData.session.access_token,
        refresh_token: sessionData.session.refresh_token,
        user_id: userId,
        has_pin: verifyData.has_pin,
        role: verifyData.role,
        full_name: verifyData.full_name,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: (err as Error).message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});