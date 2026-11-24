const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");

initializeApp();

const TYPES = new Set(["nearby_search", "nearby_category", "games_filter", "plan_created"]);

/** Keep text short so a bad client can't fill the database. */
function text(value, max) {
  return typeof value === "string" ? value.slice(0, max) : null;
}

/** Keep only up to 20 simple fields (text, number, true/false). */
function simpleMap(value) {
  const out = {};
  if (!value || typeof value !== "object") return out;
  for (const [key, v] of Object.entries(value).slice(0, 20)) {
    if (["string", "number", "boolean"].includes(typeof v)) {
      out[key.slice(0, 40)] = typeof v === "string" ? v.slice(0, 200) : v;
    }
  }
  return out;
}

/** The caller's IP address, as seen by Google's front end. */
function callerIp(rawRequest) {
  const forwarded = rawRequest.headers["x-forwarded-for"];
  if (typeof forwarded === "string" && forwarded.length > 0) {
    return forwarded.split(",")[0].trim();
  }
  return rawRequest.ip || null;
}

/**
 * Saves one search to the search_logs collection with the caller's IP address
 * and the server's time.
 */
exports.logSearch = onCall({ region: "us-central1", cors: true }, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in first.");
  }
  const data = request.data || {};
  if (!TYPES.has(data.type)) {
    throw new HttpsError("invalid-argument", "Unknown search type.");
  }

  await getFirestore().collection("search_logs").add({
    uid: request.auth.uid,
    type: data.type,
    query: text(data.query, 200),
    filters: simpleMap(data.filters),
    device: simpleMap(data.device),
    appVersion: text(data.appVersion, 40),
    ip: callerIp(request.rawRequest),
    createdAt: FieldValue.serverTimestamp(),
  });
  return { ok: true };
});

// ---------------------------------------------------------------------------
// Invite link previews
// ---------------------------------------------------------------------------
const { onRequest } = require("firebase-functions/v2/https");

const SITE = "https://festino.web.app";

/** Makes text safe to put inside HTML. */
function esc(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

/** "Fri, Feb 26 · 4:00 PM" from "2027-02-26" and minutes after midnight. */
function whenLabel(date, startMinutes) {
  const parts = [];
  if (typeof date === "string" && /^\d{4}-\d{2}-\d{2}$/.test(date)) {
    const d = new Date(`${date}T12:00:00Z`);
    parts.push(d.toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric", timeZone: "UTC" }));
  }
  if (typeof startMinutes === "number") {
    const h = Math.floor(startMinutes / 60) % 24;
    const m = startMinutes % 60;
    parts.push(`${((h + 11) % 12) + 1}:${String(m).padStart(2, "0")} ${h < 12 ? "AM" : "PM"}`);
  }
  return parts.join(" · ");
}

/**
 * /i/<inviteId>?g=<guest>: a tiny page with the invitation's own title, date and
 * cover photo for WhatsApp, iMessage and other link previews, which then opens
 * the invite in the app (/?invite=<id>&g=<guest>).
 */
exports.invitePreview = onRequest({ region: "us-central1", memory: "256MiB", maxInstances: 20 }, async (req, res) => {
  const segs = req.path.split("/").filter(Boolean);
  const id = (segs[0] === "i" ? segs[1] : segs[0] || "").replace(/[^A-Za-z0-9_-]/g, "").slice(0, 200);
  const guest = String(req.query.g || "").replace(/[^A-Za-z0-9]/g, "").slice(0, 16);
  const target = id ? `${SITE}/?invite=${encodeURIComponent(id)}${guest ? `&g=${guest}` : ""}` : `${SITE}/`;

  let title = "You're invited! 🎉";
  let description = "Open your invitation and RSVP on Festino.";
  let image = `${SITE}/icons/Icon-512.png`;
  try {
    if (id) {
      const snap = await getFirestore().doc(`invites/${id}`).get();
      if (snap.exists) {
        const d = snap.data();
        const name = typeof d.title === "string" && d.title ? d.title.slice(0, 100) : "our party";
        const place = typeof d.venue === "string" ? d.venue.slice(0, 80) : "";
        const video = d.video && ((Array.isArray(d.video.photos) && d.video.photos.length) || d.video.clip);
        const cancelled = d.status === "cancelled";
        title = cancelled ? `Cancelled: ${name}` : `You're invited: ${name} 🎉`;
        description = [whenLabel(d.date, d.startMinutes), place, cancelled ? "Tap for details" : video ? "▶ Watch the video and RSVP" : "Tap to RSVP"]
          .filter(Boolean)
          .join(" · ");
        const cover = (typeof d.photoUrl === "string" && d.photoUrl)
          || (d.video && Array.isArray(d.video.photos) && typeof d.video.photos[0] === "string" && d.video.photos[0]);
        if (cover && cover.startsWith("https://")) image = cover;
      }
    }
  } catch (e) {
    console.error("invitePreview", e);
  }

  res.set("Cache-Control", "public, max-age=300, s-maxage=300");
  res.status(200).send(`<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<title>${esc(title)}</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Festino">
<meta property="og:title" content="${esc(title)}">
<meta property="og:description" content="${esc(description)}">
<meta property="og:image" content="${esc(image)}">
<meta property="og:url" content="${esc(`${SITE}/i/${id}`)}">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="${esc(title)}">
<meta name="twitter:description" content="${esc(description)}">
<meta name="twitter:image" content="${esc(image)}">
<meta http-equiv="refresh" content="0; url=${esc(target)}">
</head><body style="font-family:sans-serif;text-align:center;padding:40px">
<p>Opening your invitation… <a href="${esc(target)}">Tap here</a> if nothing happens.</p>
<script>location.replace(${JSON.stringify(target)});</script>
</body></html>`);
});

// Festino admins. Keep this list in step with isAdmin() in firestore.rules.
const ADMIN_EMAILS = new Set(["northbitapps@gmail.com", "krishna.mula9@gmail.com", "krishnar0929@gmail.com"]);

function isAdmin(auth) {
  const t = auth && auth.token;
  return !!t && t.email_verified === true && ADMIN_EMAILS.has(String(t.email || "").toLowerCase());
}

/**
 * Admin dashboard: every sign-in account (including guests), with how they
 * signed in, when they joined and when they were last seen. Only admins.
 */
exports.adminUsers = onCall({ region: "us-central1", cors: true }, async (request) => {
  if (!isAdmin(request.auth)) {
    throw new HttpsError("permission-denied", "Admins only.");
  }
  const users = [];
  let pageToken;
  do {
    const page = await getAuth().listUsers(1000, pageToken);
    for (const u of page.users) {
      const providers = u.providerData.map((p) => p.providerId);
      users.push({
        uid: u.uid,
        email: u.email || null,
        name: u.displayName || null,
        phone: u.phoneNumber || null,
        photo: u.photoURL || null,
        providers,
        anonymous: providers.length === 0 && !u.email,
        disabled: u.disabled,
        emailVerified: u.emailVerified,
        created: u.metadata.creationTime || null,
        lastSignIn: u.metadata.lastSignInTime || null,
        lastActive: u.metadata.lastRefreshTime || u.metadata.lastSignInTime || null,
      });
    }
    pageToken = page.pageToken;
  } while (pageToken && users.length < 20000);
  return { users };
});
