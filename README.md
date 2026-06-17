# 💬 VibeTalk — Real-Time Chat App with Flutter

> A production-ready, full-stack messaging application built with **Flutter**, **Firebase**, **ZEGOCLOUD**, and **Riverpod**.

---

## 📱 Screenshots

### Light Mode

<div style="display:flex; flex-wrap:wrap; gap:8px;">
<img width="315" height="700" alt="Chat List" src="https://github.com/user-attachments/assets/73cf2dfa-2bdb-4976-936b-aae43708e791" />
<img width="315" height="700" alt="Conversation" src="https://github.com/user-attachments/assets/cb797ace-8970-4557-a51d-8988cbbfd722" />
<img width="315" height="700" alt="Voice Message" src="https://github.com/user-attachments/assets/d3308a31-cc60-42a2-98f6-4ccfdf5daf8e" />
<img width="315" height="700" alt="Profile" src="https://github.com/user-attachments/assets/85ce704c-1434-4bae-998b-ece07198e9d5" />
<img width="315" height="700" alt="Friends" src="https://github.com/user-attachments/assets/dc9dc01f-e0f4-4161-adb5-778a744bc601" />
<img width="315" height="700" alt="Call" src="https://github.com/user-attachments/assets/81292e4d-fc7d-463c-b281-d441add888ef" />
<img width="315" height="700" alt="Media Sharing" src="https://github.com/user-attachments/assets/db44fc53-f5b2-453a-9b78-1644cdba4407" />
<img width="315" height="700" alt="Reactions" src="https://github.com/user-attachments/assets/381ff46d-b72d-4322-91b9-c82effb7f22d" />
<img width="315" height="700" alt="Notifications" src="https://github.com/user-attachments/assets/7139faa3-e4cb-42d6-ab4f-ff46ed26d03d" />
<img width="315" height="700" alt="Login" src="https://github.com/user-attachments/assets/abb1c383-fa5f-4338-bd25-33d1ce810fb4" />
<img width="315" height="700" alt="Signup" src="https://github.com/user-attachments/assets/3041452a-bc32-486d-8bbc-78b36997f075" />
<img width="315" height="700" alt="Settings" src="https://github.com/user-attachments/assets/44cdcc75-e8eb-4acf-a72d-ef91bc900fc2" />
<img width="315" height="700" alt="Dark Mode Toggle" src="https://github.com/user-attachments/assets/d7bd1b9a-1fa4-45d3-a43f-b0d355e41248" />
<img width="315" height="700" alt="Reply" src="https://github.com/user-attachments/assets/e3a0d5c6-c0f4-4ba9-a1c2-30ad9267c8cb" />
<img width="315" height="700" alt="Edit Message" src="https://github.com/user-attachments/assets/79e9fc24-8f45-48f1-bd50-d854dd4394fa" />
<img width="315" height="700" alt="Online Status" src="https://github.com/user-attachments/assets/942f0cee-9a1c-4b02-90b1-af3f20da0db1" />
<img width="315" height="700" alt="Typing Indicator" src="https://github.com/user-attachments/assets/75e2c687-7649-4592-93d6-bf804a39fab9" />
<img width="315" height="700" alt="Image Preview" src="https://github.com/user-attachments/assets/6e574368-f270-4868-9f3f-570c0dec6c6e" />
<img width="315" height="700" alt="Video Message" src="https://github.com/user-attachments/assets/cc9b5322-3fbc-490c-bdda-ff7c3bc3d948" />
<img width="315" height="700" alt="Block User" src="https://github.com/user-attachments/assets/45365f7c-39cd-49d1-bc54-4cdbcf6bddbe" />
<img width="315" height="700" alt="Search" src="https://github.com/user-attachments/assets/0dcfa5ad-3c31-4778-bf7a-5299d5e60783" />
<img width="315" height="700" alt="Friend Request" src="https://github.com/user-attachments/assets/6b4a71e7-cf49-495f-92b3-8d0858ef1432" />
<img width="315" height="700" alt="Pending Requests" src="https://github.com/user-attachments/assets/30a1127f-1a73-4c1b-afa7-26a3d8297ccf" />
<img width="315" height="700" alt="Media Gallery" src="https://github.com/user-attachments/assets/beb0c190-5714-4448-85d2-5ec62adfce58" />
<img width="315" height="700" alt="Clear Chat" src="https://github.com/user-attachments/assets/164953ba-8c45-46af-b6c7-8954a7568b90" />
<img width="315" height="700" alt="App Info" src="https://github.com/user-attachments/assets/319dcdca-af93-4528-844a-28183be6c348" />
</div>

---

## ✨ Features

### 💬 Messaging
| Feature | Description |
|---|---|
| Real-time messages | Instant delivery via Firestore streams |
| Voice messages | Record & send audio with duration display |
| Image / Video / File sharing | Up to 150 MB per upload via Cloudinary |
| Message reactions | ❤️ 👍 😂 😮 😢 🙏 🔥 🎉 |
| Reply to messages | Quote any message with inline preview |
| Edit & Delete | Edit sent messages with *edited* tag |
| Read receipts | Double checkmarks when message is read |
| Typing indicators | Live "typing..." display |
| Online status & Last Seen | Real-time presence indicators |

### 📞 Calls & Notifications
| Feature | Description |
|---|---|
| Audio & Video Calls | Powered by **ZEGOCLOUD** |
| Incoming call screen | Full-screen call UI with accept/decline |
| Push Notifications | FCM via Node.js backend — messages, friend requests, call alerts |

### 👤 Social
| Feature | Description |
|---|---|
| Friend Requests | Send, accept, reject with notifications |
| Block / Unblock | Full block functionality |
| Profile editing | Avatar upload, username change |
| Avatar from camera or gallery | Cropped & uploaded to Cloudinary |

---

## 🛠️ Tech Stack

| Layer | Technology |
|---|---|
| **Framework** | Flutter (Dart) |
| **State Management** | Riverpod |
| **Authentication** | Firebase Auth (Email/Password) |
| **Database** | Cloud Firestore |
| **Push Notifications** | Firebase Cloud Messaging (FCM) |
| **Video & Audio Calls** | ZEGOCLOUD |
| **Media Storage** | Cloudinary |
| **Notification Backend** | Node.js |

---

## 🚀 Getting Started

### Prerequisites

- Flutter SDK ≥ 3.19.0
- Dart SDK ≥ 3.3.0
- A Firebase project
- A ZEGOCLOUD account
- A Cloudinary account
- A Node.js server (for push notifications)

---

### 1. Clone the Repository

```bash
git clone https://github.com/AnishTiwari5077/Flutter-_Chart_app-with-ZEGOCLOUD-and-Voice.git
cd Flutter-_Chart_app-with-ZEGOCLOUD-and-Voice
```

### 2. Install Dependencies

```bash
flutter pub get
```

### 3. Configure Secrets

All secrets are injected at build time via `dart-define` — **no hardcoded credentials**.

```bash
cp dart_defines.json.example dart_defines.json
```

Edit `dart_defines.json` and fill in your values:

```json
{
  "CLOUDINARY_CLOUD_NAME": "your_cloudinary_cloud_name",
  "CLOUDINARY_UPLOAD_PRESET": "your_upload_preset",
  "ZEGO_APP_ID": 123456789,
  "ZEGO_APP_SIGN": "your_zego_app_sign",
  "NOTIFICATION_BACKEND_URL": "http://your-server:3000",
  "FIREBASE_PROJECT_ID": "your_firebase_project_id",
  "FIREBASE_MESSAGING_SENDER_ID": "your_sender_id",
  "FIREBASE_DATABASE_URL": "https://your-project-default-rtdb.firebaseio.com",
  "FIREBASE_STORAGE_BUCKET": "your-project.firebasestorage.app",
  "FIREBASE_ANDROID_API_KEY": "your_android_api_key",
  "FIREBASE_ANDROID_APP_ID": "1:sender_id:android:app_id"
}
```

> ⚠️ `dart_defines.json` is gitignored and will never be committed.

### 4. Firebase Setup

1. Go to [Firebase Console](https://console.firebase.google.com/) → Add Project
2. Add an **Android app** with your package name
3. Download `google-services.json` → place it in `android/app/`
4. Enable **Authentication → Email/Password**
5. Enable **Cloud Firestore** and **Cloud Messaging**

#### Firestore Security Rules

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    match /users/{userId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.auth.uid == userId;
    }

    match /chats/{chatId} {
      allow read, write: if request.auth != null;
      match /messages/{messageId} {
        allow read, write: if request.auth != null;
      }
    }

    match /friendRequests/{requestId} {
      allow read, write: if request.auth != null;
    }

    match /notifications/{notificationId} {
      allow read, write: if request.auth != null;
    }
  }
}
```

### 5. Run the App

```bash
# Development
flutter run --dart-define-from-file dart_defines.json

# Release APK
flutter build apk --release --dart-define-from-file dart_defines.json

# Release AAB (Google Play)
flutter build appbundle --release --dart-define-from-file dart_defines.json
```

---

## ⚙️ Android Configuration

- **Min SDK**: 21
- **Target SDK**: 35
- **Kotlin**: 2.2.20
- **AGP**: 8.11.1
- Release builds are signed with a keystore and optimized with R8/ProGuard

---

## 🔒 Security

- Zero hardcoded credentials — all secrets via `dart-define`
- Firestore rules enforce authenticated-only access
- User documents are write-protected to their own UID
- Keystore-signed release builds

---

## ⭐ Support

If you find this project useful, give it a ⭐ on GitHub!

**Made with ❤️ using Flutter**
