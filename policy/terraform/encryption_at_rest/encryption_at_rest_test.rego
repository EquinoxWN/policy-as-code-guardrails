package terraform.encryption_at_rest_test

import data.lib.fixtures
import data.terraform.encryption_at_rest as rule

test_encrypted_resources_pass if {
	doc := fixtures.plan([
		fixtures.resource("aws_db_instance", "app", {"storage_encrypted": true}),
		fixtures.resource("aws_rds_cluster", "reports", {"storage_encrypted": true}),
		fixtures.resource("aws_ebs_volume", "data", {"encrypted": true}),
	])
	count(rule.deny) == 0 with input as doc
}

test_other_types_are_not_checked if {
	count(rule.deny) == 0 with input as fixtures.plan([fixtures.resource("aws_s3_bucket", "logs", {})])
}

test_unencrypted_database_fails if {
	doc := fixtures.plan([fixtures.resource("aws_db_instance", "reporting", {"storage_encrypted": false})])
	rule.deny == {"PAC005 aws_db_instance.reporting: storage_encrypted is not set to true"} with input as doc
}

test_unencrypted_aurora_cluster_fails if {
	doc := fixtures.plan([fixtures.resource("aws_rds_cluster", "reports", {"storage_encrypted": false})])
	rule.deny == {"PAC005 aws_rds_cluster.reports: storage_encrypted is not set to true"} with input as doc
}

test_volume_left_to_the_account_default_fails if {
	volume := fixtures.with_unknown(fixtures.resource("aws_ebs_volume", "scratch", {"size": 50}), {"encrypted": true})
	rule.deny == {"PAC005 aws_ebs_volume.scratch: encrypted is not set to true"} with input as fixtures.plan([volume])
}
