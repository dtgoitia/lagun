# Spec: run agent containerized

Status: draft

## Problem

- `flake.nix` handles a single OCI container. But we need at least 2 (agent container + OneCLI container).
- `lagun` will be used by multiple projects. To avoid conflicts, each project reuse the OCI images, but their containers must have different names.

## Goal

- `lagun` exposes a single command that spins up all its containers (so far the agent container and the OneCLI container)
