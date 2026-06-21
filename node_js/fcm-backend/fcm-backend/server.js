// server.js  –  Node.js FCM Notification Backend
// Run: node server.js
//
// Endpoints:
//   GET  /                        – health check
//   POST /send-message            – chat message notification
//   POST /send-friend-request     – friend request notification
//   POST /send-request-accepted   – friend request accepted notification
//   POST /send-notification       – generic fallback (kept for backward compatibility)
//
//   NOTE: Call notifications use /send-call which sends a DATA-ONLY
//         high-priority FCM payload so the device wakes even in killed state.

const express    = require('express');
const admin      = require('firebase-admin');
const bodyParser = require('body-parser');
const cors       = require('cors');
const rateLimit  = require('express-rate-limit');

// =======================
// CONFIG
// =======================
const PORT = process.env.PORT || 3000;

// =======================
// APP INIT
// =======================
const app = express();
app.use(cors());
app.use(express.json());  // replaces deprecated body-parser

// Rate limit: max 30 requests per minute per IP
const limiter = rateLimit({
  windowMs: 60 * 1000,
  max: 30,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, error: 'Too many requests, please try again later.' },
});
app.use(limiter);

// Request logger
app.use((req, res, next) => {
  const ts = new Date().toISOString();
  console.log(`[${ts}] ${req.method} ${req.path}`);
  next();
});

// =======================
// FIREBASE ADMIN INIT
// =======================
// On Render: set FIREBASE_SERVICE_ACCOUNT env var with the full JSON string.
// Locally:   place serviceAccountkey.json next to server.js.
let serviceAccount;
if (process.env.FIREBASE_SERVICE_ACCOUNT) {
  serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
  console.log('🔑 Using service account from environment variable');
} else {
  serviceAccount = require('./serviceAccountkey.json');
  console.log('🔑 Using service account from local serviceAccountkey.json');
}

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

console.log('✅ Firebase Admin Initialized');
console.log(`🚀 Server will start on port ${PORT}`);

// =======================
// HELPERS
// =======================

/**
 * Build a data-only FCM message (works in background/killed state on Android).
 * All values must be strings.
 */
function buildDataMessage(token, dataMap, priority = 'high') {
  return {
    token,
    data: Object.fromEntries(
      Object.entries(dataMap).map(([k, v]) => [k, String(v)])
    ),
    android: { priority },
  };
}

/** Send an FCM message and return the response. Throws on failure. */
async function sendFcm(message) {
  const response = await admin.messaging().send(message);
  console.log('✅ FCM sent:', response);
  return response;
}

/** Standard success response */
function ok(res, messageId) {
  return res.json({ success: true, messageId });
}

/** Standard error response */
function fail(res, error, status = 500) {
  console.error('❌ Error:', error.message || error);
  return res.status(status).json({ success: false, error: error.message || String(error) });
}

/** Validate required fields; returns missing fields array */
function missing(obj, fields) {
  return fields.filter(f => !obj[f]);
}

// =======================
// HEALTH CHECK
// =======================
app.get('/', (req, res) => {
  res.json({
    status : 'ok',
    message: 'VibeTalk FCM Notification Server',
    time   : new Date().toISOString(),
    endpoints: [
      'POST /send-message',
      'POST /send-friend-request',
      'POST /send-request-accepted',
      'POST /send-call',
      'POST /send-notification  (generic)',
    ],
  });
});

// =======================
// INCOMING CALL NOTIFICATION
// =======================
// Body: { token, callerName, callId, isVideo }
//
// Sends a DATA-ONLY high-priority FCM message.
// Data-only ensures _firebaseMessagingBackgroundHandler fires on Android
// in every state (killed / background / foreground). The handler then
// shows a local fullScreenIntent notification so it behaves like a call UI.
app.post('/send-call', async (req, res) => {
  try {
    const { token, callerName, callId, isVideo } = req.body;
    console.log('📞 /send-call:', { callerName, callId, isVideo });

    const required = missing(req.body, ['token', 'callerName', 'callId']);
    if (required.length) {
      return res.status(400).json({ success: false, error: `Missing fields: ${required.join(', ')}` });
    }

    const isVideoCall = String(isVideo) === 'true';
    const callLabel   = isVideoCall ? 'Incoming Video Call' : 'Incoming Voice Call';

    const message = {
      token,

      // DATA-ONLY — NO 'notification' key at any level.
      // If a notification block is present, Android shows a system FCM
      // notification that opens the app directly when tapped (bypassing
      // our Accept/Decline local notification). Data-only ensures ONLY
      // _firebaseMessagingBackgroundHandler fires and shows our custom
      // local notification with fullScreenIntent + action buttons.
      data: {
        type      : 'call',
        callId    : String(callId),
        callerName: String(callerName),
        isVideo   : String(isVideoCall),
        title     : String(callerName),
        body      : callLabel,
      },

      android: {
        priority: 'high',     // wakes Doze-mode devices

        // Call expires in 60 s — matches CallingScreen auto-cancel timer.
        // Prevents stale call notifications after the caller hangs up.
        // Firebase Admin SDK requires milliseconds as a number (not '60s').
        ttl: 60 * 1000,

        // Deduplicates retried messages for the same call.
        collapseKey: callId,

        // Required on Realme/Xiaomi — fires even in Direct Boot mode
        // (device just booted and not yet unlocked by user).
        directBootOk: true,
      },

      apns: {
        headers: {
          'apns-priority'   : '10',
          // Expire the push at the same time as the call TTL
          'apns-expiration' : String(Math.floor(Date.now() / 1000) + 60),
        },
        payload: {
          aps: { 'content-available': 1 },  // wakes iOS background
        },
      },
    };

    const response = await admin.messaging().send(message);
    console.log('✅ Call FCM sent:', response);
    return res.json({ success: true, messageId: response });
  } catch (e) {
    return fail(res, e);
  }
});

// =======================
// CHAT MESSAGE NOTIFICATION
// =======================
// Body: { token, senderName, senderId, chatId, body }
app.post('/send-message', async (req, res) => {
  try {
    const { token, senderName, senderId, chatId, body } = req.body;
    console.log('💬 /send-message:', { senderName, chatId });

    const required = missing(req.body, ['token', 'senderName', 'senderId', 'chatId', 'body']);
    if (required.length) {
      return res.status(400).json({ success: false, error: `Missing fields: ${required.join(', ')}` });
    }

    const message = buildDataMessage(token, {
      type      : 'message',
      title     : senderName,
      body,
      senderId,
      senderName,
      chatId,
    });

    const response = await sendFcm(message);
    return ok(res, response);
  } catch (e) {
    return fail(res, e);
  }
});

// =======================
// FRIEND REQUEST NOTIFICATION
// =======================
// Body: { token, senderName, senderId, requestId }
app.post('/send-friend-request', async (req, res) => {
  try {
    const { token, senderName, senderId, requestId } = req.body;
    console.log('👥 /send-friend-request:', { senderName, senderId });

    const required = missing(req.body, ['token', 'senderName', 'senderId', 'requestId']);
    if (required.length) {
      return res.status(400).json({ success: false, error: `Missing fields: ${required.join(', ')}` });
    }

    const message = buildDataMessage(token, {
      type     : 'friend_request',
      title    : 'New Friend Request',
      body     : `${senderName} sent you a friend request`,
      senderId,
      senderName,
      requestId,
    });

    const response = await sendFcm(message);
    return ok(res, response);
  } catch (e) {
    return fail(res, e);
  }
});

// =======================
// FRIEND REQUEST ACCEPTED NOTIFICATION
// =======================
// Body: { token, acceptorName, acceptorId, chatId }
app.post('/send-request-accepted', async (req, res) => {
  try {
    const { token, acceptorName, acceptorId, chatId } = req.body;
    console.log('✅ /send-request-accepted:', { acceptorName, chatId });

    const required = missing(req.body, ['token', 'acceptorName', 'acceptorId', 'chatId']);
    if (required.length) {
      return res.status(400).json({ success: false, error: `Missing fields: ${required.join(', ')}` });
    }

    const message = buildDataMessage(token, {
      type        : 'request_accepted',
      title       : 'Friend Request Accepted',
      body        : `${acceptorName} accepted your friend request`,
      userId      : acceptorId,
      acceptorName,
      chatId,
    });

    const response = await sendFcm(message);
    return ok(res, response);
  } catch (e) {
    return fail(res, e);
  }
});

// =======================
// GENERIC NOTIFICATION (backward-compatible)
// =======================
// Body: { token, title, body, data? }
app.post('/send-notification', async (req, res) => {
  try {
    const { token, title, body, data } = req.body;
    console.log('📩 /send-notification:', { title });

    const required = missing(req.body, ['token', 'title', 'body']);
    if (required.length) {
      return res.status(400).json({ success: false, error: `Missing fields: ${required.join(', ')}` });
    }

    const message = buildDataMessage(token, {
      title,
      body,
      ...(data || {}),
    });

    const response = await sendFcm(message);
    return ok(res, response);
  } catch (e) {
    return fail(res, e);
  }
});

// =======================
// 404 HANDLER
// =======================
app.use((req, res) => {
  res.status(404).json({ success: false, error: `Route not found: ${req.method} ${req.path}` });
});

// =======================
// SERVER START
// =======================
app.listen(PORT, '0.0.0.0', () => {
  console.log('');
  console.log('╔══════════════════════════════════════╗');
  console.log('║   VibeTalk FCM Notification Server   ║');
  console.log(`║   http://localhost:${PORT}              ║`);
  console.log('╚══════════════════════════════════════╝');
  console.log('');
});
