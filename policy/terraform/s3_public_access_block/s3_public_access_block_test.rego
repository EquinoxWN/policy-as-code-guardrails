package terraform.s3_public_access_block_test

import data.lib.fixtures
import data.terraform.s3_public_access_block as rule

full := {
	"block_public_acls": true,
	"block_public_policy": true,
	"ignore_public_acls": true,
	"restrict_public_buckets": true,
}

no_block := "no aws_s3_bucket_public_access_block covers this bucket"

# A bucket and a block whose bucket argument refers to it (the usual aws_s3_bucket.x.id form).
pair(name, settings) := [
	fixtures.resource("aws_s3_bucket", name, {"bucket": name}),
	fixtures.with_unknown(fixtures.resource("aws_s3_bucket_public_access_block", name, settings), {"bucket": true}),
]

# Configuration in which the block named <name> refers to the bucket named <name>.
config(name) := fixtures.config(
	"aws_s3_bucket_public_access_block", name,
	{"bucket": [$"aws_s3_bucket.{name}.id", $"aws_s3_bucket.{name}"]},
)

# The configuration of a module called "archive" whose block refers to its bucket.
archive_module := {"module_calls": {"archive": {"module": {"resources": [config("this")]}}}}

test_block_found_by_reference_passes if {
	count(rule.deny) == 0 with input as fixtures.plan_with_config(pair("logs", full), {"resources": [config("logs")]})
}

test_block_found_by_bucket_name_passes if {
	bucket := fixtures.resource("aws_s3_bucket", "logs", {"bucket": "acme-logs"})
	settings := object.union(full, {"bucket": "acme-logs"})
	block := fixtures.resource("aws_s3_bucket_public_access_block", "by_name", settings)
	count(rule.deny) == 0 with input as fixtures.plan([bucket, block])
}

test_account_level_block_covers_every_bucket if {
	bucket := fixtures.resource("aws_s3_bucket", "logs", {"bucket": "acme-logs"})
	account := fixtures.resource("aws_s3_account_public_access_block", "this", full)
	count(rule.deny) == 0 with input as fixtures.plan([bucket, account])
}

test_bucket_being_deleted_is_ignored if {
	gone := fixtures.deleted(fixtures.resource("aws_s3_bucket", "old", {"bucket": "acme-old"}))
	count(rule.deny) == 0 with input as fixtures.plan([gone])
}

test_module_instances_each_with_a_block_pass if {
	resources := [rc |
		some key in ["2025", "2026"]
		some part in pair("this", full)
		rc := fixtures.in_module(part, $`module.archive["{key}"]`)
	]
	count(rule.deny) == 0 with input as fixtures.plan_with_config(resources, archive_module)
}

test_bucket_without_block_fails if {
	bucket := fixtures.resource("aws_s3_bucket", "uploads", {"bucket": "acme-uploads"})
	rule.deny == {$"PAC001 aws_s3_bucket.uploads: {no_block}"} with input as fixtures.plan([bucket])
}

test_block_with_settings_off_names_them if {
	settings := object.union(full, {"block_public_acls": false, "restrict_public_buckets": false})
	doc := fixtures.plan_with_config(pair("site", settings), {"resources": [config("site")]})
	expected := concat("", [
		"PAC001 aws_s3_bucket.site: aws_s3_bucket_public_access_block.site ",
		"leaves block_public_acls, restrict_public_buckets off",
	])
	rule.deny == {expected} with input as doc
}

test_setting_unknown_at_plan_time_counts_as_off if {
	resources := pair("site", object.remove(full, ["ignore_public_acls"]))
	doc := fixtures.plan_with_config(resources, {"resources": [config("site")]})
	expected := "PAC001 aws_s3_bucket.site: aws_s3_bucket_public_access_block.site leaves ignore_public_acls off"
	rule.deny == {expected} with input as doc
}

test_block_in_another_module_instance_does_not_cover if {
	[bucket, block] := pair("this", full)
	resources := [
		fixtures.in_module(bucket, `module.archive["2025"]`),
		fixtures.in_module(bucket, `module.archive["2026"]`),
		fixtures.in_module(block, `module.archive["2026"]`),
	]
	expected := $`PAC001 module.archive["2025"].aws_s3_bucket.this: {no_block}`
	rule.deny == {expected} with input as fixtures.plan_with_config(resources, archive_module)
}

test_block_for_another_count_index_does_not_cover if {
	[bucket, block] := pair("data", full)
	resources := [fixtures.indexed(bucket, 0), fixtures.indexed(bucket, 1), fixtures.indexed(block, 0)]
	doc := fixtures.plan_with_config(resources, {"resources": [config("data")]})
	rule.deny == {$"PAC001 aws_s3_bucket.data[1]: {no_block}"} with input as doc
}

test_partial_account_block_does_not_cover if {
	bucket := fixtures.resource("aws_s3_bucket", "logs", {"bucket": "acme-logs"})
	settings := object.union(full, {"block_public_policy": false})
	account := fixtures.resource("aws_s3_account_public_access_block", "this", settings)
	rule.deny == {$"PAC001 aws_s3_bucket.logs: {no_block}"} with input as fixtures.plan([bucket, account])
}

test_block_for_a_different_bucket_does_not_cover if {
	bucket := fixtures.resource("aws_s3_bucket", "logs", {"bucket": "acme-logs"})
	settings := object.union(full, {"bucket": "acme-other"})
	block := fixtures.resource("aws_s3_bucket_public_access_block", "other", settings)
	rule.deny == {$"PAC001 aws_s3_bucket.logs: {no_block}"} with input as fixtures.plan([bucket, block])
}
