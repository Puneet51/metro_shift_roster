import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { SignJWT } from "https://deno.land/x/jose@v4.14.4/index.ts"

// Declare Deno namespace for VS Code TypeScript analyzer
declare const Deno: {
  env: {
    get(key: string): string | undefined;
  };
};

// Helper to get Google OAuth2 Token from Service Account
async function getAccessToken({ clientEmail, privateKey }: { clientEmail: string; privateKey: string }): Promise<string> {
  const pemHeader = "-----BEGIN PRIVATE KEY-----";
  const pemFooter = "-----END PRIVATE KEY-----";
  const cleanKey = privateKey
    .replace(pemHeader, "")
    .replace(pemFooter, "")
    .replace(/\\n/g, "")
    .replace(/\s+/g, "");

  const binaryDer = Uint8Array.from(atob(cleanKey), (c) => c.charCodeAt(0));
  const ecPrivateKey = await crypto.subtle.importKey(
    "pkcs8",
    binaryDer.buffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const jwt = await new SignJWT({
    iss: clientEmail,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
  })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuedAt()
    .setExpirationTime("1h")
    .sign(ecPrivateKey);

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  const data = await res.json();
  return data.access_token;
}

serve(async (req: Request) => {
  try {
    const { record } = await req.json();

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    const projectId = Deno.env.get("FIREBASE_PROJECT_ID") ?? "";
    const clientEmail = Deno.env.get("FIREBASE_CLIENT_EMAIL") ?? "";
    const privateKey = Deno.env.get("FIREBASE_PRIVATE_KEY") ?? "";

    // 1. Get user profile and FCM Token
    const { data: profile } = await supabase
      .from("profiles")
      .select("fcm_token")
      .eq("id", record.user_id)
      .single();

    if (!profile?.fcm_token) {
      return new Response(JSON.stringify({ message: "No FCM token for user" }), { status: 200 });
    }

    // 2. Fetch OAuth2 Token
    const accessToken = await getAccessToken({ clientEmail, privateKey });

    // 3. Send FCM v1 Message
    const fcmUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;
    const fcmMessage = {
      message: {
        token: profile.fcm_token,
        notification: {
          title: record.title,
          body: record.body,
        },
        android: {
          priority: "HIGH",
          notification: {
            channel_id: "metro_shift_high_importance_channel",
            notification_priority: "PRIORITY_MAX",
            visibility: "PUBLIC",
            sound: "default",
            icon: "launcher_icon",
            color: "#1E3A8A",
          },
        },
        data: {
          click_action: "FLUTTER_NOTIFICATION_CLICK",
          notification_id: String(record.id),
        },
      },
    };

    const pushRes = await fetch(fcmUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify(fcmMessage),
    });

    const pushData = await pushRes.json();
    return new Response(JSON.stringify(pushData), { headers: { "Content-Type": "application/json" } });
  } catch (err: unknown) {
    const errorMessage = err instanceof Error ? err.message : String(err);
    return new Response(JSON.stringify({ error: errorMessage }), { status: 500 });
  }
});