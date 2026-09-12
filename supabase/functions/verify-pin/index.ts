import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: corsHeaders,
  });
}

function createInternalPassword(): string {
  return crypto.randomUUID().replaceAll("-", "");
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const body = await req.json();
    const phone = String(body?.phone ?? "").trim();
    const pin = String(body?.pin ?? "").trim();

    if (!phone || !pin) {
      return jsonResponse(
        { error: "Phone and PIN are required", debug_stage: stage },
        400,
      );
    }

    const cleanPhone = phone.replace(/\D/g, "");

    if (!cleanPhone) {
      return jsonResponse(
        { error: "Invalid phone number", debug_stage: stage },
        400,
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !serviceRoleKey) {

      return jsonResponse(
        { error: "Authentication service is not configured", debug_stage: stage },
        500,
      );
    }

    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    });

    // ------------------------------------------------------------
    // 1. Verify application PIN
    // ------------------------------------------------------------

    const { data: verifyData, error: verifyErr } =
      await supabaseAdmin.rpc("verify_user_custom_pin_by_phone", {
        p_phone: cleanPhone,
        p_pin: pin,
      });

    if (verifyErr) {

      return jsonResponse(
        {
          error: "Unable to verify PIN. Please try again.",
        },
        500,
      );
    }

    if (!verifyData?.success) {
      return jsonResponse(
        {
          error: verifyData?.error ?? "Incorrect PIN entered",
        },
        401,
      );
    }

    const userId = String(verifyData.user_id ?? "");

    if (!userId) {

      return jsonResponse(
        {
          error: "Invalid user account configuration",
        },
        500,
      );
    }

    // ------------------------------------------------------------
    // 2. Internal Auth credentials
    // ------------------------------------------------------------

    const internalEmail =
      `employee_${userId}@auth.metroshift.internal`;
    const internalPassword = createInternalPassword();

    // ------------------------------------------------------------
    // 3. Look up Auth user
    // ------------------------------------------------------------

    const { data: existingResult, error: existingErr } =
      await supabaseAdmin.auth.admin.getUserById(userId);

    if (existingErr) {

      if (!/not found/i.test(existingErr.message)) {
        return jsonResponse(
          {
            error: "getUserById failed: " + existingErr.message,
          },
          500,
        );
      }
    }

    let authUserId = userId;

    // ------------------------------------------------------------
    // 4A. First login: create clean Auth account through GoTrue
    // ------------------------------------------------------------
    if (!existingResult?.user) {

      const { data: createdResult, error: createErr } =
        await supabaseAdmin.auth.admin.createUser({
          id: userId,
          email: internalEmail,
          password: internalPassword,
          email_confirm: true,
          user_metadata: {
            role: verifyData.role,
            full_name: verifyData.full_name,
          },
        });

      if (createErr || !createdResult?.user) {

        const { data: concurrentResult, error: concurrentErr } =
          await supabaseAdmin.auth.admin.getUserById(userId);

        if (concurrentErr || !concurrentResult?.user) {
          return jsonResponse(
            {
              error:
                createErr?.message ??
                "Unable to create the authentication account.",
            },
            500,
          );
        }

        authUserId = concurrentResult.user.id;
      } else {
        authUserId = createdResult.user.id;
      }
    } else {
      // ----------------------------------------------------------
      // 4B. Existing Auth account
      // ----------------------------------------------------------
      authUserId = existingResult.user.id;

      const { error: updateErr } =
        await supabaseAdmin.auth.admin.updateUserById(authUserId, {
          email: internalEmail,
          password: internalPassword,
          email_confirm: true,
          user_metadata: {
            role: verifyData.role,
            full_name: verifyData.full_name,
          },
        });

      if (updateErr) {

        return jsonResponse(
          {
            error: "updateUserById failed: " + updateErr.message,
          },
          500,
        );
      }

    }

    // ------------------------------------------------------------
    // 5. Return credentials to Flutter
    // ------------------------------------------------------------

    return jsonResponse({
      success: true,
      email: internalEmail,
      password: internalPassword,
      user_id: authUserId,
      has_pin: verifyData.has_pin,
      role: verifyData.role,
      full_name: verifyData.full_name,
    });
  } catch (err) {

    return jsonResponse(
      {
        error:
          err instanceof Error
            ? err.message
            : "Unexpected authentication error",
      },
      500,
    );
  }
});