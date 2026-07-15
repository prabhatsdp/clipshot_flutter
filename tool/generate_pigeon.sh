#!/bin/sh
set -eu

dart run pigeon \
  --input pigeons/clipshot_api.dart \
  --package_name clipshot \
  --dart_out lib/src/generated/clipshot_api.g.dart \
  --kotlin_out android/src/main/kotlin/com/prabhatpandey/clipshot/ClipshotApi.g.kt \
  --kotlin_package com.prabhatpandey.clipshot \
  --swift_out ios/Classes/ClipshotApi.g.swift
