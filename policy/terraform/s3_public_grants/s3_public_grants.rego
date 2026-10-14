# METADATA
# title: "PAC002: no S3 ACL or bucket policy grants access to everyone"
# description: >-
#   Public canned ACLs, ACL grants to the AllUsers or AuthenticatedUsers groups, and bucket policy
#   statements that allow any principal without a condition that narrows who can call.
# entrypoint: true
# custom:
#   id: PAC002
#   severity: critical
package terraform.s3_public_grants

import data.lib.tfplan

public_canned_acls := {"public-read", "public-read-write", "authenticated-read"}

public_groups := {
	"http://acs.amazonaws.com/groups/global/AllUsers",
	"http://acs.amazonaws.com/groups/global/AuthenticatedUsers",
}

# Condition keys that limit a statement to known networks, accounts or principals, so a
# wildcard principal is not public (the same keys S3 uses to decide that a policy is public).
narrowing_keys := {
	"aws:principalaccount",
	"aws:principalarn",
	"aws:principalorgid",
	"aws:principalorgpaths",
	"aws:sourceaccount",
	"aws:sourcearn",
	"aws:sourceip",
	"aws:sourceowner",
	"aws:sourcevpc",
	"aws:sourcevpce",
	"aws:userid",
}

deny contains msg if {
	some acl in tfplan.resources_of("aws_s3_bucket_acl")
	canned := tfplan.after(acl, "acl", "")
	canned in public_canned_acls
	msg := $"PAC002 {acl.address}: canned ACL {canned} opens the bucket beyond the account"
}

deny contains msg if {
	some acl in tfplan.resources_of("aws_s3_bucket_acl")
	some policy in tfplan.list(tfplan.after(acl, "access_control_policy", []))
	some grant in tfplan.list(policy.grant)
	some grantee in tfplan.list(grant.grantee)
	grantee.uri in public_groups
	msg := $"PAC002 {acl.address}: grants {grant.permission} to {grantee.uri}"
}

deny contains msg if {
	some resource in tfplan.resources_of("aws_s3_bucket_policy")
	some statement in statements(tfplan.after(resource, "policy", ""))
	statement.Effect == "Allow"
	wildcard_principal(statement.Principal)
	not narrowed(statement)
	sid := object.get(statement, "Sid", "(no Sid)")
	what := actions(statement)
	msg := $"PAC002 {resource.address}: statement {sid} allows {what} to any principal without a narrowing condition"
}

# Statements of a policy document given as a JSON string; none when it is unknown or invalid.
statements(document) := doc.Statement if {
	json.is_valid(document)
	doc := json.unmarshal(document)
	is_array(doc.Statement)
} else := [doc.Statement] if {
	json.is_valid(document)
	doc := json.unmarshal(document)
	is_object(doc.Statement)
} else := []

# "*", {"AWS": "*"} and {"AWS": ["*"]} all mean anyone.
wildcard_principal("*")

wildcard_principal(principal) if principal.AWS == "*"

wildcard_principal(principal) if "*" in tfplan.list(principal.AWS)

# True when the statement has a condition on at least one narrowing key.
narrowed(statement) if {
	some keys in statement.Condition
	some key, _ in keys
	lower(key) in narrowing_keys
}

# The statement's actions as one readable string.
actions(statement) := concat(", ", statement.Action) if is_array(statement.Action)

else := statement.Action if is_string(statement.Action)

else := "every action outside NotAction"
