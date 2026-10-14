# METADATA
# title: "PAC001: every S3 bucket has a full public access block"
# description: >-
#   A bucket is safe from accidental public ACLs and policies only when all four public access
#   block settings are on, either in a bucket-level block or in an account-level block.
# entrypoint: true
# custom:
#   id: PAC001
#   severity: high
package terraform.s3_public_access_block

import data.lib.tfplan

settings := ["block_public_acls", "block_public_policy", "ignore_public_acls", "restrict_public_buckets"]

# Settings of a public access block that are not planned as true (unknown counts as off).
off(block) := [setting | some setting in settings; tfplan.after(block, setting, false) != true]

# A block applies to a bucket by bucket name, or by reference inside the same module instance.
covers(block, bucket) if {
	name := tfplan.after(bucket, "bucket", "")
	name != ""
	tfplan.after(block, "bucket", "") == name
}

covers(block, bucket) if {
	tfplan.module_address(block) == tfplan.module_address(bucket)
	$"{bucket.type}.{bucket.name}" in tfplan.references(block, "bucket")
	same_instance(block, bucket)
}

# With count or for_each on both sides, a block pairs with the bucket of the same index.
same_instance(block, bucket) if tfplan.instance_key(block) == tfplan.instance_key(bucket)

same_instance(block, _) if not "index" in object.keys(block)

same_instance(_, bucket) if not "index" in object.keys(bucket)

# An account-level block with all four settings on protects every bucket in the account.
account_blocked if {
	some block in tfplan.resources_of("aws_s3_account_public_access_block")
	count(off(block)) == 0
}

deny contains msg if {
	not account_blocked
	some bucket in tfplan.resources_of("aws_s3_bucket")
	not any_block(bucket)
	msg := $"PAC001 {bucket.address}: no aws_s3_bucket_public_access_block covers this bucket"
}

deny contains msg if {
	not account_blocked
	some bucket in tfplan.resources_of("aws_s3_bucket")
	some block in tfplan.resources_of("aws_s3_bucket_public_access_block")
	covers(block, bucket)
	disabled := off(block)
	count(disabled) > 0
	msg := $"PAC001 {bucket.address}: {block.address} leaves {concat(", ", disabled)} off"
}

# True when at least one bucket-level block covers the bucket.
any_block(bucket) if {
	some block in tfplan.resources_of("aws_s3_bucket_public_access_block")
	covers(block, bucket)
}
