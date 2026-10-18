# SpotiFLAC 5.1.1 build 162 — Opus scan fix

Install the arm64 APK on the Motorola moto g75 5G. The armv7 APK is for 32-bit devices. Each APK installs independently.

Source commit: 6500a82. Valid Opus comments no longer require title/artist/ReplayGain fields. Parser errors are preserved for remaining failures. Rust tests, Android JVM tests, Flutter metadata tests, and package/signature checks passed. Physical-device verification is pending.

Signed with the same development key as build 161. Install over the previous build, then run a full local-library rescan. No uninstall, file conversion, or library reset is required. Sign into GitHub to download from this private repository.
