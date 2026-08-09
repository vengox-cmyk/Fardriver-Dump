# All commands run inside the `flutter` Docker container — no local toolchain required.
.PHONY: build up down shell pub-get analyze test coverage format format-check build-linux build-apk android-check check

build:
	docker compose build

up:
	docker compose up -d

down:
	docker compose down

shell:
	docker compose run --rm flutter bash

pub-get:
	docker compose run --rm flutter flutter pub get

analyze:
	docker compose run --rm flutter flutter analyze --no-fatal-infos

test:
	docker compose run --rm flutter flutter test

coverage:
	docker compose run --rm flutter flutter test --coverage

format:
	docker compose run --rm flutter dart format lib test

format-check:
	docker compose run --rm flutter dart format --set-exit-if-changed lib test

build-linux:
	docker compose run --rm flutter flutter build linux

build-apk:
	docker compose run --rm flutter flutter build apk

android-check:
	./tooling/check_android_config.sh

# Run all pre-commit checks in the container.
check: format-check analyze test
