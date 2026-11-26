#!/bin/bash
set -e

# Install Flutter (stable) kalau belum ada
if [ ! -d "flutter" ]; then
  git clone https://github.com/flutter/flutter.git --depth 1 -b stable flutter
fi

export PATH="$PATH:$(pwd)/flutter/bin"

flutter config --enable-web
flutter precache --web
flutter pub get
flutter build web --release