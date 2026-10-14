# METADATA
# title: "PAC005: databases and volumes are encrypted at rest"
# description: >-
#   RDS instances, Aurora clusters and EBS volumes must set encryption explicitly. Encryption
#   cannot be switched on later without copying the data, and an unset value is not trusted:
#   it is reported, not assumed to follow an account default.
# entrypoint: true
# custom:
#   id: PAC005
#   severity: high
package terraform.encryption_at_rest

import data.lib.tfplan

# The attribute that turns on encryption at rest, per resource type.
encryption_attribute := {
	"aws_db_instance": "storage_encrypted",
	"aws_ebs_volume": "encrypted",
	"aws_rds_cluster": "storage_encrypted",
}

deny contains msg if {
	some rc in tfplan.resources
	attribute := encryption_attribute[rc.type]
	tfplan.after(rc, attribute, false) != true
	msg := $"PAC005 {rc.address}: {attribute} is not set to true"
}
