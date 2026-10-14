package terraform.required_tags_test

import data.lib.fixtures
import data.terraform.required_tags as rule

complete := {"owner": "platform-team", "environment": "prod", "cost_center": "cc-1042"}

test_tags_from_provider_defaults_pass if {
	volume := fixtures.resource("aws_ebs_volume", "data", {"tags": null, "tags_all": complete})
	count(rule.deny) == 0 with input as fixtures.plan([volume])
}

test_tag_value_known_only_after_apply_counts if {
	known := object.remove(complete, ["owner"])
	volume := fixtures.resource("aws_ebs_volume", "data", {"tags": null, "tags_all": known})
	count(rule.deny) == 0 with input as fixtures.plan([fixtures.with_unknown(volume, {"tags_all": {"owner": true}})])
}

test_resource_tags_count_when_tags_all_is_unknown if {
	volume := fixtures.with_unknown(fixtures.resource("aws_ebs_volume", "data", {"tags": complete}), {"tags_all": true})
	count(rule.deny) == 0 with input as fixtures.plan([volume])
}

test_resources_without_tag_support_are_not_checked if {
	doc := fixtures.plan([
		fixtures.resource("aws_s3_bucket_policy", "p", {"policy": "{}"}),
		fixtures.resource("aws_security_group_rule", "r", {"type": "ingress"}),
	])
	count(rule.deny) == 0 with input as doc
}

test_missing_tags_are_listed_in_order if {
	tags := {"owner": "data-team"}
	volume := fixtures.resource("aws_ebs_volume", "scratch", {"tags": tags, "tags_all": tags})
	expected := "PAC006 aws_ebs_volume.scratch: missing required tags cost_center, environment"
	rule.deny == {expected} with input as fixtures.plan([volume])
}

test_empty_or_blank_values_do_not_count if {
	tags := object.union(complete, {"owner": "", "environment": "  "})
	bucket := fixtures.resource("aws_s3_bucket", "logs", {"tags": tags, "tags_all": tags})
	expected := "PAC006 aws_s3_bucket.logs: missing required tags environment, owner"
	rule.deny == {expected} with input as fixtures.plan([bucket])
}

test_untagged_resource_fails_with_every_tag if {
	vpc := fixtures.resource("aws_vpc", "main", {"tags": null, "tags_all": {}})
	expected := "PAC006 aws_vpc.main: missing required tags cost_center, environment, owner"
	rule.deny == {expected} with input as fixtures.plan([vpc])
}
