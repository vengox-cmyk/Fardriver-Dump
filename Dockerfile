# ArcDash Flutter build/test container.
# Includes Flutter SDK, Android SDK and Java.
# Source: https://github.com/cirruslabs/docker-images-flutter
# Pin the image digest so a future `stable` tag cannot silently change the
# compiler, Android SDK, or Java toolchain used by CI and local builds.
FROM ghcr.io/cirruslabs/flutter:stable@sha256:46691e311715845de03a3ba4753a475476936805b29431b1f00f1816981033f8

# Treat the mounted repo as a trusted git worktree (avoids "dubious ownership" errors).
RUN git config --global --add safe.directory /app

# Disable Flutter analytics/telemetry inside the container.
RUN flutter config --no-analytics

# Default working directory matches the compose volume mount.
WORKDIR /app
