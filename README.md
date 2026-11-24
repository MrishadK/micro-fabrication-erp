# ⚙️ Micro — Industrial Fabrication & Workshop Management Suite

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Android-1A237E)](https://github.com)
[![Database](https://img.shields.io/badge/Database-SQLite%20(Offline--First)-003B57?logo=sqlite&logoColor=white)](https://sqlite.org)
[![Cloud Sync](https://img.shields.io/badge/Cloud%20Sync-Google%20Drive-4285F4?logo=googledrive&logoColor=white)](https://drive.google.com)
[![License](https://img.shields.io/badge/License-Proprietary%20%2F%20Open-FF6D00)](#license)

**Micro** is a high-performance, offline-first Enterprise Resource Planning (ERP) and Workshop Management System designed specifically for fabrication units, metal workshops, manufacturing facilities, and industrial service contractors.

Available seamlessly across **Windows Desktop Workstations** and **Android Mobile Devices**, Micro connects your workshop floor to the front desk with zero lag and real-time Google Drive cloud synchronization.

---

## 🌟 Key Highlights

- 🖥️ **Tailored Desktop Workstation**: A modern, high-density desktop shell with collapsible sidebar navigation, quick action bars, and widescreen data cards — designed specifically for PC monitors and laptops.
- 📱 **Mobile Floor Companion**: Full-featured companion experience on Android for floor supervisors to track work orders and log attendance on the go.
- ☁️ **Two-Way Android ↔ PC Google Drive Sync**: Seamlessly restore your entire Android database onto your PC with one click. Automatic cloud backups to the `MICRO BACKUP` folder keep all your devices in sync.
- 📑 **Instant PDF Invoicing & Receipts**: Generate GST-compliant invoices, scrap value deductions, advance payment receipts, and delivery challans on the fly.
- 👷 **Comprehensive Wage & Payroll Engine**: Track worker attendance, piece rates, daily wages, overtime (OT), and produce individual PDF pay slips.
- 🤖 **AI Database Auditor**: Intelligent anomaly detection powered by Google Gemini (with graceful offline rule-based fallbacks) that checks for negative balances or wage mismatches.
- 🛡️ **Offline-First & 100% Private**: Powered by local SQLite databases (`fab_shop_pro.db`). Your business data never touches third-party servers without your explicit permission.

---

## 📸 Workstation Screenshots & UI Tour

| Desktop Workstation Dashboard | Android ↔ PC Cloud Restore |
|:---:|:---:|
| Dual-pane layout, quick job creation, real-time status | 1-Click Google Drive restore from Android phone |

---

## 🚀 Core Features

### 1. 📋 Work Order & Job Tracking
- Log fabrication orders with client details, work descriptions, and target delivery quantities.
- Track stage-by-stage deliveries and remaining quantity balances.
- Filter and search active orders by job status: `Pending`, `In Progress`, `Delivered`, `Archived`.
- Client order history and payment records with itemized summaries.

### 2. 💰 Invoicing, Billing & Cash Flow
- Real-time calculations: Total Cost, Advance Paid, Scrap Metal Value Deduction, and Net Balance Due.
- Built-in PDF invoice generator (`pdf` & `printing`) ready for direct printing or WhatsApp/Email sharing.
- Partial payment tracking with timestamped transaction logs.
- Business Financial Summary: Export date-range financial summaries and materials reports.

### 3. 👷 Worker Attendance & Payroll Management
- Supports dual wage modes:
  - **Daily Wage**: Regular shifts, half-days, and custom hourly overtime (OT).
  - **Piece Rate**: Pay calculated directly by units produced or tasks completed.
- Locked wage rate history prevents historical wage calculation errors.
- One-click weekly/monthly PDF Wage Slip export.

### 4. ☁️ Google Drive Cross-Platform Sync
- **Jump from Phone to PC**: Existing Android users can connect their Google account on PC and instantly restore all historical records.
- **Auto-Backup on Launch**: Automatically uploads the latest `backup_<timestamp>.db` to Google Drive when the app starts.
- **Local File Import/Export**: Manual backup to USB drive or local storage (`.db`) without requiring an internet connection.

---

## 🏗️ Architecture & Technology Stack

```
Micro Suite
 ├── Presentation Layer (Flutter Material 3)
 │    ├── Desktop Shell (Sidebar Navigation Rail + Top Action Header)
 │    ├── Mobile Shell (Custom Navigation Bar + FAB)
 │    └── Riverpod State Management
 ├── Business Logic & Services
 │    ├── GoogleDriveService (OAuth2 Loopback on Desktop / Google Sign-In on Mobile)
 │    ├── AiAuditorService (Gemini 2.5 Flash + Local Heuristic Engine)
 │    ├── PdfService & WagePdfService (Vector PDF Generation)
 │    └── GoogleDriveServiceDesktop (Local File Picker & DB Transfer)
 └── Data Layer
      ├── SQLite (sqflite_common_ffi for Desktop / sqflite for Android)
      ├── Local Storage (fab_shop_pro.db)
      └── SharedPreferences (Cached credentials & user preferences)
```

| Component | Technology |
|---|---|
| **Framework** | Flutter 3.x (Dart 3.x) |
| **State Management** | Flutter Riverpod |
| **Local Database** | SQLite (`sqflite` + `sqflite_common_ffi`) |
| **Cloud Storage** | Google Drive API v3 (`googleapis`, `googleapis_auth`) |
| **PDF Engine** | `pdf` & `printing` |
| **Excel Migration** | `excel` |
| **AI Auditor** | Google Gemini (`generativelanguage.googleapis.com`) |
| **Security / Biometrics** | `local_auth` (Fingerprint / Windows Hello) |

---

## 💻 Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (`^3.8.1` or higher)
- [Dart SDK](https://dart.dev/get-dart)
- For Windows Desktop: Visual Studio with "Desktop development with C++" workload installed
- For Android: Android Studio & Android SDK

### 1. Clone the Repository
```bash
git clone https://github.com/YOUR_USERNAME/Micro-Fabrication-ERP.git
cd Micro-Fabrication-ERP
```

### 2. Install Dependencies
```bash
flutter pub get
```

### 3. Setup Credentials (Optional)
To enable Google Drive Cloud Sync and the Gemini AI Auditor in your own environment:
- **Google OAuth**: Copy `android/app/google-services.json.example` to `android/app/google-services.json` and insert your Google OAuth Client ID.
- **Gemini API Key**: Provide your API key at compile time using `--dart-define`:
  ```bash
  flutter run -d windows --dart-define=GEMINI_API_KEY=your_gemini_api_key
  ```
  *(If omitted, the app automatically uses the intelligent offline local auditor).*

### 4. Run the Application
- **Windows Desktop Workstation**:
  ```bash
  flutter run -d windows
  ```
- **Android Mobile**:
  ```bash
  flutter run -d android
  ```

---

## 🔒 Security & Privacy Notice

This repository adheres to strict security hygiene:
- ✅ **No Private Keystores**: Android release `.jks` signing keys are excluded from git.
- ✅ **No Leaked Secrets**: Production API tokens and OAuth client secrets are kept out of version control.
- ✅ **No Plaintext Databases**: Local customer records and wage data remain on the user's device and personal Google Drive account only.

---

## 📦 Building for Production

### Build Windows Desktop Installer / EXE
```bash
flutter build windows --release
```
Output executable: `build/windows/x64/runner/Release/micro.exe`

### Build Android APK / App Bundle
```bash
flutter build apk --release
# OR for Google Play Store:
flutter build appbundle --release
```

---

## 👨‍💻 Author & Credits

- **Developer**: Rishad
- **Designed for**: Modern Fabrication Workshops, Industrial Manufacturing, and Metal Service Centers.

---

## 📄 License

This software is released under the **MIT License** (or your organization's preferred license). See the [LICENSE](LICENSE) file for details.
