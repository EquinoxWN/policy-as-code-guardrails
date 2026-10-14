# METADATA
# title: Terraform plan helpers
# description: >-
#   Reads the JSON that `terraform show -json <planfile>` prints. Shared by every guardrail, so
#   each rule works on resources that will exist after apply and on known planned values only.
package lib.tfplan

# Managed resources that will exist after apply: created, updated, replaced or unchanged.
resources contains rc if {
	some rc in input.resource_changes
	rc.mode == "managed"
	rc.change.after != null
}

# Planned resources of one type.
resources_of(type) := {rc | some rc in resources; rc.type == type}

# Planned value of an attribute, or the default when it is null or only known after apply.
after(rc, key, default_value) := value if {
	value := rc.change.after[key]
	value != null
} else := default_value

# The value itself when it is an array, otherwise an empty array.
list(value) := value if is_array(value)

else := []

# Module instance address of a resource; empty in the root module.
module_address(rc) := object.get(rc, "module_address", "")

# Instance key of a resource created with count or for_each; null otherwise.
instance_key(rc) := object.get(rc, "index", null)

# Module path without instance keys: module.a["x"].module.b[0] becomes module.a.module.b.
module_path(rc) := regex.replace(module_address(rc), `\[[^\]]*\]`, "")

# Address the configuration uses for a resource: module path, type and name, no instance keys.
config_address(rc) := $"{module_path(rc)}.{rc.type}.{rc.name}" if module_path(rc) != ""

else := $"{rc.type}.{rc.name}"

# Every managed resource block of the configuration, keyed by its module path and address.
configs[key] := resource if {
	walk(input.configuration.root_module, [path, resource])
	path[count(path) - 2] == "resources"
	resource.mode == "managed"
	key := concat("", array.concat(module_prefixes(path), [resource.address]))
}

# "module.<name>." for every module call on a configuration path, outermost first.
module_prefixes(path) := [$"module.{path[i + 1]}." | some i, step in path; step == "module_calls"]

# Addresses, relative to the resource's module, that one of its configured arguments refers to.
references(rc, argument) := {ref | some ref in configs[config_address(rc)].expressions[argument].references}
