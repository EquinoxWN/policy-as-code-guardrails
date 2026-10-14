package lib.tfplan_test

import data.lib.fixtures
import data.lib.tfplan

test_resources_keep_planned_managed_resources_only if {
	bucket := fixtures.resource("aws_s3_bucket", "kept", {"bucket": "kept"})
	gone := fixtures.deleted(fixtures.resource("aws_s3_bucket", "gone", {"bucket": "gone"}))
	lookup := object.union(fixtures.resource("aws_s3_bucket", "lookup", {}), {"mode": "data"})
	addresses := {rc.address | some rc in tfplan.resources} with input as fixtures.plan([bucket, gone, lookup])
	addresses == {"aws_s3_bucket.kept"}
}

test_resources_of_filters_by_type if {
	bucket := fixtures.resource("aws_s3_bucket", "a", {})
	volume := fixtures.resource("aws_ebs_volume", "b", {})
	result := tfplan.resources_of("aws_ebs_volume") with input as fixtures.plan([bucket, volume])
	{rc.address | some rc in result} == {"aws_ebs_volume.b"}
}

test_after_returns_known_values_and_defaults_otherwise if {
	volume := fixtures.resource("aws_ebs_volume", "v", {"size": 20, "type": null})
	rc := fixtures.with_unknown(volume, {"encrypted": true})
	tfplan.after(rc, "size", 0) == 20
	tfplan.after(rc, "type", "gp3") == "gp3"
	tfplan.after(rc, "encrypted", false) == false
}

test_list_turns_non_arrays_into_empty_arrays if {
	tfplan.list(["a"]) == ["a"]
	tfplan.list(null) == []
	tfplan.list("a") == []
}

test_module_path_strips_instance_keys if {
	bucket := fixtures.resource("aws_s3_bucket", "this", {})
	rc := fixtures.in_module(bucket, `module.archive["2025"].module.inner[0]`)
	tfplan.module_path(rc) == "module.archive.module.inner"
	tfplan.config_address(rc) == "module.archive.module.inner.aws_s3_bucket.this"
	tfplan.config_address(fixtures.resource("aws_s3_bucket", "root", {})) == "aws_s3_bucket.root"
}

test_references_resolve_in_root_and_nested_modules if {
	block_type := "aws_s3_bucket_public_access_block"
	root_block := fixtures.resource(block_type, "root", {})
	inner_block := fixtures.in_module(fixtures.resource(block_type, "this", {}), `module.outer["a"].module.inner`)
	root_refs := {"bucket": ["aws_s3_bucket.root.id", "aws_s3_bucket.root"]}
	inner_refs := {"bucket": ["aws_s3_bucket.this.id", "aws_s3_bucket.this"]}
	inner := {"module": {"resources": [fixtures.config(block_type, "this", inner_refs)]}}
	root_module := {
		"resources": [fixtures.config(block_type, "root", root_refs)],
		"module_calls": {"outer": {"module": {"module_calls": {"inner": inner}}}},
	}
	doc := fixtures.plan_with_config([root_block, inner_block], root_module)
	tfplan.references(root_block, "bucket") == {"aws_s3_bucket.root.id", "aws_s3_bucket.root"} with input as doc
	tfplan.references(inner_block, "bucket") == {"aws_s3_bucket.this.id", "aws_s3_bucket.this"} with input as doc
	tfplan.references(root_block, "policy") == set() with input as doc
}
