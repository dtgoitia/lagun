#!/usr/bin/env bash
set -euo pipefail

file="specs/$1.md"

cat << 'EOF' > "$file"
---
status: draft
---

## Summary

## Context

## Requirements

## Constraints

## Out of scope

EOF
