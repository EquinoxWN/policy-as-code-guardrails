# METADATA
# title: "PAC004: no database instance is publicly accessible"
# description: >-
#   publicly_accessible = true gives an RDS or Aurora instance an address that resolves to a
#   public IP, so one open security group rule is enough to expose it to the internet.
# entrypoint: true
# custom:
#   id: PAC004
#   severity: critical
package terraform.db_public_access

import data.lib.tfplan

database_types := {"aws_db_instance", "aws_rds_cluster_instance"}

deny contains msg if {
	some db in tfplan.resources
	db.type in database_types
	tfplan.after(db, "publicly_accessible", false) == true
	msg := $"PAC004 {db.address}: publicly_accessible is true, so the instance gets a public address"
}
