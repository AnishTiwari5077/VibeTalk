// server.js
// Run: node server.js

const express = require('express');
const admin = require('firebase-admin');
const bodyParser = require('body-parser');
const cors = require('cors');

// =======================
// CONFIG
// =======================
const PORT = 3000;

// =======================
// APP INIT
// =======================
const app = express();
app.use(cors());
app.use(bodyParser.json());

// =======================
// FIREBASE ADMIN INIT
// =======================
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

console.log('✅ Firebase Admin Initialized');

// =======================
// HEALTH CHECK
// =======================
app.get('/', (req, res) => {
  res.json({
    status: 'ok',
    message: 'FCM Notification Server Running',
    time: new Date().toISOString(),
  });
});

// =======================
// SEND SINGLE NOTIFICATION
// =======================
app.post('/send-notification', async (req, res) => {
  try {
    const { token, title, body, data } = req.body;

    console.log('📩 Request:', req.body);

    if (!token || !title || !body) {
      return res.status(400).json({
        success: false,
        error: 'token, title, body are required',
      });
    }

    const message = {
      token: token,
      notification: {
        title: title,
        body: body,
      },
      data: data || {},
      android: {
        priority: 'high',
        notification: {
          channelId: 'chat_channel',
          sound: 'default',
        },
      },
    };

    const response = await admin.messaging().send(message);

    console.log('✅ Sent:', response);

    res.json({
      success: true,
      messageId: response,
    });
  } catch (error) {
    console.error('❌ Error:', error);

    res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});

// =======================
// SEND CALL NOTIFICATION
// =======================
app.post('/send-call', async (req, res) => {
  try {
    const { token, callerName, callerId, chatId } = req.body;

    console.log('📞 Call Request:', req.body);

    if (!token || !callerName || !callerId) {
      return res.status(400).json({
        success: false,
        error: 'token, callerName, callerId are required',
      });
    }

    // Send data-only message for background handling in Flutter
    const message = {
      token: token,
      data: {
        type: 'call',
        callerName: callerName,
        callerId: callerId,
        chatId: chatId || '',
      },
      android: {
        priority: 'high',
      },
    };

    const response = await admin.messaging().send(message);

    console.log('✅ Call Notification Sent:', response);

    res.json({
      success: true,
      messageId: response,
    });
  } catch (error) {
    console.error('❌ Call Notification Error:', error);

    res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});

// =======================
// SERVER START
// =======================
app.listen(PORT, '0.0.0.0', () => {
  console.log('🚀 Server started');
  console.log(`📍 http://localhost:${PORT}`);
});
