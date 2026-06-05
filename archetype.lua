-- platform-application-manifests-library standalone / one-shot entry point.
--
-- Parents wanting to consume this library should depend on it with
-- `library: true` and call `require("platform-application-manifests").run(context, opts)`.
-- This script runs when the archetype is invoked directly to retrofit an existing project:
--
--   archetect render .../platform-application-manifests-library <project-dir>

local context = Context.new()
require("lib").run(context)
return context
