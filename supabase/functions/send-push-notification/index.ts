import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

// Generate Google OAuth2 Access Token for FCM v1
async function getAccessToken(serviceAccount: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const claim = {
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    exp: now + 3600,
    iat: now,
  };

  const header = { alg: "RS256", typ: "JWT" };
  const encodedHeader = btoa(JSON.stringify(header));
  const encodedClaim = btoa(JSON.stringify(claim));
  const unsignedToken = `${encodedHeader}.${encodedClaim}`;

  // Clean and import RSA Private Key
  const pem = serviceAccount.private_key
    .replace(/\\n/g, "\n")
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");

  const binaryDerString = atob(pem);
  const binaryDer = new Uint8Array(binaryDerString.length);
  for (let i = 0; i < binaryDerString.length; i++) {
    binaryDer[i] = binaryDerString.charCodeAt(i);
  }

  const key = await crypto.subtle.importKey(
    "pkcs8",
    binaryDer.buffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsignedToken)
  );

  const encodedSignature = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");

  const jwt = `${unsignedToken}.${encodedSignature}`;

  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  const tokenJson = await tokenRes.json();
  if (!tokenJson.access_token) {
    throw new Error(`Failed to get OAuth token: ${JSON.stringify(tokenJson)}`);
  }

  return tokenJson.access_token;
}

serve(async (req) => {
  try {
    const payload = await req.json();
    console.log("📥 Incoming Webhook Payload:", JSON.stringify(payload));

    const record = payload.record ?? payload;
    const userId = record.user_id;
    const title = record.title || "New Notification";
    const body = record.body || "";

    if (!userId) {
      return new Response(JSON.stringify({ error: "Missing user_id" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Initialize Supabase Client to fetch the user's current FCM token
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const { data: profile, error: profileErr } = await supabase
      .from("profiles")
      .select("fcm_token")
      .eq("id", userId)
      .maybeSingle();

    if (profileErr || !profile || !profile.fcm_token) {
      console.log(`⚠️ No active FCM token found for user ${userId}`);
      return new Response(JSON.stringify({ status: "skipped_no_token" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Firebase Service Account Credentials from Supabase Secrets
    const serviceAccount: ServiceAccount = {
      project_id: Deno.env.get("FIREBASE_PROJECT_ID")!,
      client_email: Deno.env.get("FIREBASE_CLIENT_EMAIL")!,
      private_key: Deno.env.get("FIREBASE_PRIVATE_KEY")!,
    };

    const accessToken = await getAccessToken(serviceAccount);

    // Send Push Notification via Firebase v1 HTTP API
    const fcmUrl = `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`;
    const fcmMessage = {
      message: {
        token: profile.fcm_token,
        notification: {
          title: title,
          body: body,
        },
        android: {
          priority: "high",
          notification: {
            channel_id: "high_importance_channel",
            sound: "default",
          },
        },
        data: {
          click_action: "FLUTTER_NOTIFICATION_CLICK",
          notification_id: record.id ?? "",
          type: record.type ?? "general",
        },
      },
    };

    const fcmRes = await fetch(fcmUrl, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(fcmMessage),
    });

    const fcmResult = await fcmRes.json();
    console.log("🚀 FCM Response:", JSON.stringify(fcmResult));

    return new Response(JSON.stringify({ success: true, result: fcmResult }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("❌ Edge Function Error:", error);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});