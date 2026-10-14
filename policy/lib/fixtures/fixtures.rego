# METADATA
# title: Unit test fixtures
# description: >-
#   Builders for small documents shaped like `terraform show -json` output, so each test states
#   only the attributes its rule reads. Used by the *_test.rego files; no rule depends on it.
package lib.fixtures

# A planned managed resource in the root module.
resource(type, name, after) := {
	"address": $"{type}.{name}",
	"mode": "managed",
	"type": type,
	"name": name,
	"change": {"actions": ["create"], "after": after, "after_unknown": {}},
}

# The resource with some attributes only known after apply.
with_unknown(rc, unknown) := object.union(rc, {"change": {"after_unknown": unknown}})

# The resource placed in a module instance, such as module.archive["2025"].
in_module(rc, module_address) := object.union(rc, {
	"module_address": module_address,
	"address": $"{module_address}.{rc.address}",
})

# The resource as instance <index> of a count or for_each.
indexed(rc, index) := object.union(rc, {
	"index": index,
	"address": $"{rc.address}[{json.marshal(index)}]",
})

# The resource planned for deletion.
deleted(rc) := object.union(rc, {"change": {"actions": ["delete"], "after": null}})

# A plan holding the given resource changes.
plan(resources) := {"resource_changes": resources}

# A plan holding resource changes and the root module of its configuration.
plan_with_config(resources, root_module) := {
	"resource_changes": resources,
	"configuration": {"root_module": root_module},
}

# A configured resource whose arguments refer to other resources.
config(type, name, references) := {
	"address": $"{type}.{name}",
	"mode": "managed",
	"type": type,
	"name": name,
	"expressions": {argument: {"references": refs} | some argument, refs in references},
}
