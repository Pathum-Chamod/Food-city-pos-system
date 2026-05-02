# Food City POS

Flutter desktop POS application for Windows.

## Build Windows `.exe`

Prerequisites on the build computer:

- Flutter SDK with Windows desktop support enabled
- Visual Studio Build Tools / Visual Studio with **Desktop development with C++**
- Windows 10 or newer

From the repository root, run:

```powershell
.\scripts\build_pos_windows.ps1
```

To also create a distributable zip file, run:

```powershell
.\scripts\build_pos_windows.ps1 -Zip
```

## Output

The executable is created at:

```text
apps\pos_app\build\windows\x64\runner\Release\FoodCityPOS.exe
```

Important: copy or zip the whole `Release` folder when installing on another computer. Flutter Windows apps need the `.exe`, `data` folder, Flutter DLLs, and plugin DLLs together.

If `-Zip` is used, the package is created at:

```text
dist\FoodCityPOS-windows-x64.zip
```

## Run The App

Open:

```text
FoodCityPOS.exe
```

The app title and Windows file metadata are configured as **Food City POS**.

## Backend Sync

The current POS sync endpoint is configured in:

```text
lib\services\sync_service.dart
```

It currently points to the local development backend:

```text
http://127.0.0.1:8080/api/pos_sync.php
```

For production, update `apiUrl` to the live backend before building, or keep the local server running on the POS computer.
