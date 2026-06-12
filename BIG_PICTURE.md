Main goal: set up an 24/7 assistant (X) to find second hard cars.

For safety reasons, X must run on an isolated environment, to limite the possible harm of a malicious prompt injection or other attacks. Also, X must be accessible from many devices, so running it on my home laptop is not convenient. I have decided to run it on a VPS, which I will provision using OpenTofu. This VPS will run NixOS for reproducibility convenience, and it will specifically use nix flakes for its definition. X must run on a podman container inside NixOS, and will be exposed to the public internet using Caddy.

I want to avoid public registries, because I'm a solo developer, so I will just build the podman container image locally, upload it to the VPS manually, and point NixOS to the just-uploaded image.

To develop X, I will set up a repo (A). This repo must be friendly both to human-only developers and to coding agents. The coding agent (A_agent) must run isolated inside a container, to protect the host from malicious prompt injections, agent/human mistakes, etc. The credentials that the A_agent will use (for example, Athropic API keys) must never be inside the A_agent container, but injected by OneCLI (HTTP proxy).

Equally, the credentials must be passed securely to X as well on runtime in the VPS, using also OneCLI in production.

Lastly, I am aware that this setup (human+agent development environment + deployed_agent) will be required in many other projects of mine, so I abstract away common tools/practices (like running the agent in a container, safely inject credentials into outgoing HTTP calls, etc.) in a separate project (B) that can be reused and shared across many projects. B must not be a repo that I copy-paste and I never look back at. B must be an actual development dependency (a framework if you wish) that I can just plug and update.

So, recapping:

- sub-goal 1: set up the B repository
- sub-goal 2: set up the A repository reusing B
- final and main goal: set up an 24/7 assistant (X) to find second hard cars.
