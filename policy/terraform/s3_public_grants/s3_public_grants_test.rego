package terraform.s3_public_grants_test

import data.lib.fixtures
import data.terraform.s3_public_grants as rule

# A bucket policy resource holding the given statements as a JSON string, as the plan shows it.
bucket_policy(name, statements) := fixtures.resource(
	"aws_s3_bucket_policy", name,
	{"policy": json.marshal({"Version": "2012-10-17", "Statement": statements})},
)

all_users := "http://acs.amazonaws.com/groups/global/AllUsers"

beyond := "opens the bucket beyond the account"

to_anyone := "to any principal without a narrowing condition"

test_private_acl_passes if {
	acl := fixtures.resource("aws_s3_bucket_acl", "logs", {"acl": "private"})
	count(rule.deny) == 0 with input as fixtures.plan([acl])
}

test_grant_to_a_named_account_passes if {
	grantee := {"type": "CanonicalUser", "id": "79a59df900b949e55d96a1e698fbaced"}
	policy := {"grant": [{"permission": "READ", "grantee": [grantee]}]}
	acl := fixtures.resource("aws_s3_bucket_acl", "logs", {"access_control_policy": [policy]})
	count(rule.deny) == 0 with input as fixtures.plan([acl])
}

test_deny_statement_with_wildcard_principal_passes if {
	doc := fixtures.plan([bucket_policy("tls_only", [{
		"Effect": "Deny", "Principal": "*", "Action": "s3:*", "Resource": "arn:aws:s3:::acme/*",
		"Condition": {"Bool": {"aws:SecureTransport": "false"}},
	}])])
	count(rule.deny) == 0 with input as doc
}

test_allow_to_one_account_passes if {
	doc := fixtures.plan([bucket_policy("partner", [{
		"Effect": "Allow", "Principal": {"AWS": "arn:aws:iam::111122223333:root"},
		"Action": "s3:GetObject", "Resource": "arn:aws:s3:::acme/*",
	}])])
	count(rule.deny) == 0 with input as doc
}

test_wildcard_narrowed_to_a_vpc_endpoint_passes if {
	doc := fixtures.plan([bucket_policy("vpce", [{
		"Effect": "Allow", "Principal": "*", "Action": "s3:GetObject", "Resource": "arn:aws:s3:::acme/*",
		"Condition": {"StringEquals": {"aws:SourceVpce": "vpce-0a1b2c3d"}},
	}])])
	count(rule.deny) == 0 with input as doc
}

test_policy_unknown_at_plan_time_is_left_to_pac001 if {
	unknown := fixtures.with_unknown(fixtures.resource("aws_s3_bucket_policy", "later", {}), {"policy": true})
	count(rule.deny) == 0 with input as fixtures.plan([unknown])
}

test_public_canned_acls_fail if {
	canned := ["public-read", "public-read-write", "authenticated-read"]
	acls := [fixtures.resource("aws_s3_bucket_acl", acl, {"acl": acl}) | some acl in canned]
	rule.deny == {
		$"PAC002 aws_s3_bucket_acl.public-read: canned ACL public-read {beyond}",
		$"PAC002 aws_s3_bucket_acl.public-read-write: canned ACL public-read-write {beyond}",
		$"PAC002 aws_s3_bucket_acl.authenticated-read: canned ACL authenticated-read {beyond}",
	} with input as fixtures.plan(acls)
}

test_grant_to_all_users_fails if {
	policy := {"grant": [{"permission": "READ", "grantee": [{"type": "Group", "uri": all_users}]}]}
	acl := fixtures.resource("aws_s3_bucket_acl", "site", {"access_control_policy": [policy]})
	rule.deny == {$"PAC002 aws_s3_bucket_acl.site: grants READ to {all_users}"} with input as fixtures.plan([acl])
}

test_every_wildcard_principal_form_fails if {
	both := ["s3:GetObject", "s3:PutObject"]
	doc := fixtures.plan([
		bucket_policy("star", [{"Sid": "A", "Effect": "Allow", "Principal": "*", "Action": "s3:GetObject"}]),
		bucket_policy("aws_star", [{"Sid": "B", "Effect": "Allow", "Principal": {"AWS": "*"}, "Action": "s3:GetObject"}]),
		bucket_policy("aws_list", [{"Effect": "Allow", "Principal": {"AWS": ["*"]}, "Action": both}]),
	])
	rule.deny == {
		$"PAC002 aws_s3_bucket_policy.star: statement A allows s3:GetObject {to_anyone}",
		$"PAC002 aws_s3_bucket_policy.aws_star: statement B allows s3:GetObject {to_anyone}",
		$"PAC002 aws_s3_bucket_policy.aws_list: statement (no Sid) allows s3:GetObject, s3:PutObject {to_anyone}",
	} with input as doc
}

test_condition_that_does_not_narrow_who_still_fails if {
	doc := fixtures.plan([bucket_policy("tls", [{
		"Sid": "Tls", "Effect": "Allow", "Principal": "*", "Action": "s3:GetObject",
		"Condition": {"Bool": {"aws:SecureTransport": "true"}},
	}])])
	rule.deny == {$"PAC002 aws_s3_bucket_policy.tls: statement Tls allows s3:GetObject {to_anyone}"} with input as doc
}

test_single_statement_object_with_not_action_fails if {
	statement := {"Sid": "All", "Effect": "Allow", "Principal": "*", "NotAction": "s3:DeleteObject"}
	policy := json.marshal({"Statement": statement})
	doc := fixtures.plan([fixtures.resource("aws_s3_bucket_policy", "single", {"policy": policy})])
	expected := $"PAC002 aws_s3_bucket_policy.single: statement All allows every action outside NotAction {to_anyone}"
	rule.deny == {expected} with input as doc
}
