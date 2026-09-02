<div align="center">

# 🚇 Namma Metro Shift Roster System
**Next-Generation Transit Workforce & Real-Time Roster Management System**

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Supabase](https://img.shields.io/badge/Supabase-Database%20%26%20Auth-3ECF8E?logo=supabase&logoColor=white)](https://supabase.com)
[![Firebase](https://img.shields.io/badge/Firebase-Cloud%20Messaging-FFCA28?logo=firebase&logoColor=black)](https://firebase.google.com)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

<br />

<p align="center">
  <a href="https://metroshiftroster.web.app">
    <img src="https://img.shields.io/badge/Launch%20Web%20Portal-1E3A8A?style=for-the-badge&logo=googlechrome&logoColor=white" height="42" alt="Web Portal" />
  </a>
  &nbsp;&nbsp;
  <a href="https://metroshiftroster.web.app/downloads/metro_shift_roster.apk">
    <img src="https://img.shields.io/badge/Download%20Android%20APK-22C55E?style=for-the-badge&logo=android&logoColor=white" height="42" alt="Download APK" />
  </a>
</p>

</div>

---

## 📱 App Highlights & Features

| Role | Core Capabilities |
| :--- | :--- |
| 🛡️ **Administrator** | Broadcast real-time version updates, station/line configurations, account activation control, and roster master tables. |
| 👷‍♂️ **Station Supervisor** | Shift generation, real-time duty assignments, operator shift swaps, and attendance confirmations. |
| 🚆 **Train Operator** | Secure phone + PIN sign-in, daily roster alerts, geo-verified attendance punching, and duty handover tracking. |

---

## 📲 Installation & Platform Access

### 🤖 Android
1. Tap the **Download Android APK** button above or download the `.apk` file from the **Releases** section.
2. Open the downloaded file on your Android device.
3. If prompted, allow **Install from Unknown Sources**.
4. Launch **Metro Shift Roster** and verify your registered phone number.

---

### 🍏 iOS (iPhone / iPad) — Install as Progressive Web App (PWA)

Because iOS operators and supervisors run the official web portal directly with full native capabilities:

1. Open **Safari** on your iPhone or iPad.
2. Navigate to: **`https://metroshiftroster.web.app`**
3. Tap the **Share** icon (the square with an arrow pointing upward) at the bottom toolbar.
4. Scroll down the menu and select **Add to Home Screen**.
5. Name the icon **Metro Shift** and tap **Add** in the top right corner.
6. The app is now installed on your iOS home screen as a standalone, distraction-free application without browser address bars!

---

## 🛠️ Tech Stack & Architecture

* **Framework:** Flutter (Mobile & Web)
* **Backend:** Supabase (PostgreSQL, Row-Level Security, Realtime RPCs)
* **State Management:** Flutter Riverpod
* **Notifications:** Firebase Cloud Messaging (FCM)
* **Location Validation:** Geolocator (Geofenced Station Punch-in)

---

## 💻 Local Development Setup

```bash
# 1. Clone the repository
git clone [https://github.com/](https://github.com/)<your-username>/metro_shift_roster.git

# 2. Navigate to project
cd metro_shift_roster

# 3. Install packages
flutter pub get

# 4. Run application
flutter run -d chrome     # Web
flutter run -d android    # Android