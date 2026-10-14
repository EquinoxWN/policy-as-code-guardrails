# METADATA
# title: "PAC006: every taggable resource carries the required tags"
# description: >-
#   owner, environment and cost_center must be present and non-empty on every resource that
#   supports tags, counting the provider's default_tags (tags_all). Without them nobody can be
#   paged for a resource, find what belongs to production, or charge its cost to a team.
# entrypoint: true
# custom:
#   id: PAC006
#   severity: medium
package terraform.required_tags

import data.lib.tfplan

required := {"owner", "environment", "cost_center"}

deny contains msg if {
	some rc in tfplan.resources
	taggable(rc)
	missing := {key | some key in required; not tagged(rc, key)}
	count(missing) > 0
	msg := $"PAC006 {rc.address}: missing required tags {concat(", ", sort(missing))}"
}

# A resource supports tags when the AWS provider plans a tags_all map for it.
taggable(rc) if "tags_all" in object.keys(rc.change.after)

taggable(rc) if "tags_all" in object.keys(object.get(rc.change, "after_unknown", {}))

# A tag counts when its planned value is a non-empty string, or when it is only known after apply.
tagged(rc, key) if {
	some attribute in ["tags_all", "tags"]
	value := tfplan.after(rc, attribute, {})[key]
	is_string(value)
	trim_space(value) != ""
}

tagged(rc, key) if {
	some attribute in ["tags_all", "tags"]
	rc.change.after_unknown[attribute][key] == true
}
