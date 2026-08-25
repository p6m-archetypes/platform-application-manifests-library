-- platform-application-manifests-library main module.
--
-- Generates the .platform/kubernetes/ directory tree for any service archetype:
--   base/application.yaml             — PlatformApplication CRD
--   base/application_customizations.yaml — kustomize image path config
--   base/kustomization.yaml
--   {dev,stg,prd}/kustomization.yaml
--   {dev,stg,prd}/application_patch.yaml
--
-- Two-phase API (call prompt first so project-name is in context):
--
--   local platform = require("platform-application-manifests")
--   platform.prompt(context)           -- fills any missing keys
--   directory.render("contents", context)  -- parent renders its own files
--   platform.finalize(context, { destination = context:get("project-name") })
--
-- One-shot API:
--   require("platform-application-manifests").run(context, { destination = "billing-service" })
--
-- Standalone retrofit (all keys prompted interactively):
--   archetect render .../platform-application-manifests-library <project-dir>
--
-- Context contract (keys prompt() fills if absent):
--   project-name      — kebab-case service name (p6m-identity-library, or prompted here)
--   database_name     — the platform-provisioned database; defaults to project-name
--   org-solution-name — kebab-case org/solution slug (e.g. acme-payments); used in image path
--   image_registry    — container image registry hostname (e.g. registry.example.com); no default
--   protocol          — REST / gRPC / GraphQL
--   service_port      — integer, default 8080 (REST/GraphQL) or 50051 (gRPC)
--   management_port   — integer, default service_port+1 (health/metrics for all protocols)
--   persistence       — None / PostgreSQL / MySQL
--   cache             — None / Redis
--   messaging         — None / Kafka / Pulsar

local M = {}

--- The image registry, on its own so a parent can ask it EARLY.
---
--- It is a deployment fact that belongs beside the solution slug, but `prompt()` runs last (it
--- needs the resource selections), so an archetype calling only `prompt()` ends up asking for the
--- registry after Source Control — dead last in the derived interface a form is rendered from.
--- Calling this up front puts it where it belongs; `prompt()` then finds it already answered and
--- skips it. One definition either way: the library that consumes the key owns the prompt.
---
--- Idempotent, like every prompt in this library.
function M.prompt_registry(context)
    if not context:get("image_registry") then
        context:prompt_text("Image Registry:", "image_registry", {
            placeholder = "registry.example.com",
            help        = "Container image registry hostname (e.g. ghcr.io, 123456789.dkr.ecr.us-east-1.amazonaws.com)",
        })
    end
    return context
end

-- Fill any context keys needed for template rendering. Skips keys already
-- present so parent archetypes can pre-populate the full context and this
-- function becomes a no-op for all pre-set keys.
function M.prompt(context, opts)
    opts = opts or {}

    -- Parent archetypes set project_name through p6m-identity-library; standalone renders prompt
    -- for it. The prefix-name + suffix-name reconstruction that used to live here is gone with the
    -- decomposition itself (S1) — there is one project name now, and it is asked for directly.
    if not context:get("project-name") then
        context:prompt_text("Project Name:", "project_name", {
            cases = Cases.programming(),
            placeholder = "billing-service",
            help = "Kebab-case service name — matches the service's project directory.",
        })
    end

    -- The platform-provisioned database's name. Defaulted to the project so a service archetype
    -- need not think about it; an OVERLAY overrides it (`{application}_db`) because it retrofits a
    -- legacy app that may already carry a database of its own, and the two must not collide.
    -- This used to ride `{{ entity_name }}_{{ suffix_name }}`, which is how an overlay smuggled a
    -- "_db" suffix through an identity decomposition that meant nothing to it.
    if not context:get("database_name") then
        context:set("database_name", context:get("project_name"))
    end

    -- Org/solution slug — used in image path; set by the identity library in parent archetypes
    if not context:get("org-solution-name") then
        context:prompt_text("Org / Solution:", "org_solution_name", {
            cases       = Cases.programming(),
            placeholder = "my-org",
            help        = "Kebab-case org and solution slug (e.g. acme-payments)",
        })
    end

    M.prompt_registry(context)

    -- Protocol
    if not context:get("protocol") then
        context:prompt_select("Protocol:", "protocol", {
            "REST", "gRPC", "GraphQL",
        }, { default = "REST" })
    end

    local protocol = context:get("protocol")

    -- Service port
    if not context:get("service_port") then
        local default_port = (protocol == "gRPC") and 50051 or 8080
        context:prompt_int("Service port:", "service_port", { default = default_port })
    end

    -- Management port — always required (health/metrics server runs on this port for all protocols)
    if not context:get("management_port") then
        local svc_port = context:get("service_port") or 8080
        context:prompt_int("Management port:", "management_port", { default = svc_port + 1 })
    end

    -- Derived template helpers (idempotent — skip if already set by parent)
    if not context:get("port_protocol") then
        context:set("port_protocol", (protocol == "gRPC") and "grpc" or "http")
    end

    -- Resources
    if not context:get("persistence") then
        context:prompt_select("Persistence:", "persistence", {
            "None", "PostgreSQL", "MySQL",
        }, { default = "None" })
    end

    if not context:get("cache") then
        context:prompt_select("Cache:", "cache", {
            "None", "Redis",
        }, { default = "None" })
    end

    if not context:get("messaging") then
        context:prompt_select("Messaging:", "messaging", {
            "None", "Kafka", "Pulsar",
        }, { default = "None" })
    end

    return context
end

-- Render the .platform/kubernetes/ directory tree.
-- opts.destination — project subdirectory under the archetect destination root
--   (e.g. "billing-service"). Omit or pass "" when running standalone with the
--   destination already set to the project directory.
function M.finalize(context, opts)
    opts = opts or {}
    local d = opts.destination
    if d and d ~= "" then
        directory.render("contents", context, { destination = d })
    else
        directory.render("contents", context)
    end
    return context
end

-- Convenience: prompt + finalize.
function M.run(context, opts)
    M.prompt(context, opts)
    M.finalize(context, opts)
    return context
end

return M
