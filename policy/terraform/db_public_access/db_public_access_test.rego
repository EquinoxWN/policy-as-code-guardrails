package terraform.db_public_access_test

import data.lib.fixtures
import data.terraform.db_public_access as rule

public := "publicly_accessible is true, so the instance gets a public address"

test_private_and_unset_instances_pass if {
	doc := fixtures.plan([
		fixtures.resource("aws_db_instance", "private", {"publicly_accessible": false}),
		fixtures.resource("aws_db_instance", "unset", {"publicly_accessible": null}),
		fixtures.resource("aws_rds_cluster_instance", "private", {"publicly_accessible": false}),
	])
	count(rule.deny) == 0 with input as doc
}

test_public_instance_being_deleted_is_ignored if {
	gone := fixtures.deleted(fixtures.resource("aws_db_instance", "old", {"publicly_accessible": true}))
	count(rule.deny) == 0 with input as fixtures.plan([gone])
}

test_public_db_instance_fails if {
	doc := fixtures.plan([fixtures.resource("aws_db_instance", "reporting", {"publicly_accessible": true})])
	rule.deny == {$"PAC004 aws_db_instance.reporting: {public}"} with input as doc
}

test_public_aurora_instance_fails if {
	doc := fixtures.plan([fixtures.resource("aws_rds_cluster_instance", "reader", {"publicly_accessible": true})])
	rule.deny == {$"PAC004 aws_rds_cluster_instance.reader: {public}"} with input as doc
}
