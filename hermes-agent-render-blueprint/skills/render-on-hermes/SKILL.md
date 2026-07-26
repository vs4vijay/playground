---
name: render-on-hermes
description: Use whenever any other render-* skill loads, or any time the user asks you to do something on Render. Tells you that this Hermes container has the Render MCP server pre-registered with full MCP tool access for the provided API key and that the `render` CLI is NOT installed in this image, so skip every "install MCP", "install CLI", and "run render CLI" step that upstream render-* skills describe.
version: 1.0.0
author: Render
license: MIT
metadata:
  hermes:
    tags: [Render, MCP, Operations, Bootstrap, Security]
    related_skills: [render-mcp, render-deploy, render-debug, render-monitor, render-blueprints]
---

# Render on Hermes

This Hermes deployment is pre-wired for Render. The other `render-*` skills
(pulled from `github.com/render-oss/skills`) are written for generic AI coding
tools like Cursor and Claude Code, so they assume you might need to install the
CLI or configure MCP yourself. **Skip all of that.** Use this skill as the
source of truth for what is wired up here, what is NOT, and what to do when an
upstream skill assumes something that isn't true on this host.

## What's already done for you

| Capability               | State on this container                                     |
|--------------------------|-------------------------------------------------------------|
| Render MCP server        | Registered in `config.yaml` as `render`                     |
| MCP transport            | HTTP, `https://mcp.render.com/mcp`                          |
| MCP auth                 | `Authorization: Bearer ${RENDER_MCP_API_KEY}` (lazy-substituted) |
| MCP tool scope           | **Full MCP tool access** for the provided API key            |
| Render CLI               | **Not installed.** See "About the render-cli skill" below   |
| Skill bundle             | `github.com/render-oss/skills` at a pinned commit, exposed via `skills.external_dirs` |

## Default scope: full MCP access

The `render` MCP server is registered without a `tools.include` filter. You
can see every MCP tool that the provided `RENDER_MCP_API_KEY` can use,
including tools that mutate resources (`restart_service`, `update_service`,
`update_environment_variables`, `trigger_deploy`, `create_web_service`,
`query_render_postgres`, etc.).

Selecting a workspace is required context for many MCP calls. If no workspace
is selected, call `mcp_render_list_workspaces` and choose the obvious workspace
if there is only one. If there are multiple plausible workspaces, ask the user
which one to use. Do not block inspection just because workspace selection is
needed.

If the user asks you to mutate Render resources, treat the request as allowed
by this setup, but be explicit about the effect before acting. The real
permission boundary is the Render role behind `RENDER_MCP_API_KEY` and who can
reach the Hermes dashboard.

## About the `render-cli` skill (and why it's misleading here)

The upstream skill bundle includes a `render-cli` skill that describes how to
use the `render` binary for things MCP can't do (live log streaming,
`render psql`, SSH into running instances, etc.). **The CLI is not installed
in this container.** If the upstream `render-cli` skill loads, treat its
commands as a reference for what the USER can run from their own machine,
not for what you can run yourself.

When the user asks you to do something the upstream skill says needs the
CLI:

- If an MCP equivalent exists, use that. `list_logs` instead of `render logs`,
  `get_metrics` instead of `render metrics`, etc.
- If no MCP equivalent exists (live log streaming, interactive `psql`,
  SSH session, image-backed service creation), draft the CLI command and
  hand it to the user to run from their own shell. Don't try to run it
  from your `terminal` tool — the command will fail with "render: command
  not found".
- If the user really needs the agent to drive the CLI, ask before installing
  anything or adding `RENDER_API_KEY`. Download and inspect installer scripts
  before running them.

## How MCP tools appear

Hermes prefixes MCP tools with `mcp_<server>_<tool>`. So when an upstream
skill says "call `list_services()`", on Hermes you call:

```
mcp_render_list_services()
```

You usually don't need to type the prefix yourself — the agent picks the
right tool from descriptions. But when reading the upstream skill catalog,
mentally map every bare MCP tool name (`list_services`, `get_metrics`,
`list_logs`, `query_render_postgres`, etc.) to `mcp_render_<name>`.

## Steps to skip in other render-* skills

When loading any other `render-*` skill, ignore these sections entirely —
they're already handled (or deliberately not handled):

- **"Set up Render MCP" / "Add to ~/.cursor/mcp.json" / "claude mcp add"**
  → MCP is already configured as `render`. If `mcp_render_list_services`
  works, you're done.
- **"Install Render CLI" / "brew install render" / `curl ... install.sh`**
  → CLI is deliberately NOT installed. See the section above.
- **"Run `render login` or set `RENDER_API_KEY`"**
  → Neither applies. MCP uses `RENDER_MCP_API_KEY` and reads it lazily
  from the gateway env via `config.yaml` substitution.
- **"Pick a workspace"**
  → Still applies. Call
  `mcp_render_get_selected_workspace` first; if none is selected, call
  `mcp_render_list_workspaces`, then `mcp_render_select_workspace` for the
  only/obvious workspace. Ask the user only when multiple workspaces are
  plausible.

## Quick verification

If anything looks broken, the only check that matters is whether MCP works:

```
mcp_render_list_services()
```

If that returns a list, MCP is wired up and the agent can read workspace
state. If it returns 401 or doesn't appear as a registered tool at all,
the gateway didn't see `RENDER_MCP_API_KEY` at startup. Tell the user to
add it under **Environment** in the Render Dashboard and **Restart
gateway** on the Hermes Status tab.

## When to load which skill

- Deploying something new → `render-deploy`, then `render-blueprints` if multi-service
- A live service is misbehaving → `render-debug`
- Health/metrics dashboards → `render-monitor`
- Picking the right resource type (web vs worker vs cron, etc.) → the matching
  `render-web-services`, `render-background-workers`, `render-cron-jobs`, `render-static-sites`, `render-private-services`, `render-workflows` skill
- Picking the right datastore → `render-postgres` or `render-keyvalue`
- Networking / domains / disks / scaling → the same-named skill
- Migrating off Heroku → `render-migrate-from-heroku`
- "How do I do X from the command line" → consult `render-cli` for reference,
  but don't try to run the commands yourself (see "About the render-cli skill" above)

## You are running ON Render

One subtlety: this Hermes container is itself a Render web service. If the
user asks you to "look at this service" without naming one, they usually
mean the very service you're running inside. Find it with:

```
mcp_render_list_services()
```

…and look for the service name they used when they deployed this template
(default: `hermes`). Don't suggest changes to that service casually. Restarting
it kills your own session.
