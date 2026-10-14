package terraform.sg_open_ingress_test

import data.lib.fixtures
import data.terraform.sg_open_ingress as rule

# An inline ingress or egress entry of aws_security_group, with every field the plan shows.
entry(protocol, from, to, ipv4, ipv6) := {
	"protocol": protocol, "from_port": from, "to_port": to,
	"cidr_blocks": ipv4, "ipv6_cidr_blocks": ipv6,
	"prefix_list_ids": [], "security_groups": [], "self": false, "description": "",
}

# An aws_security_group with inline ingress and egress entries.
group(name, ingress, egress) := fixtures.resource("aws_security_group", name, {"ingress": ingress, "egress": egress})

# A standalone aws_vpc_security_group_ingress_rule.
vpc_rule(name, protocol, from, to, ipv4) := fixtures.resource(
	"aws_vpc_security_group_ingress_rule", name,
	{"ip_protocol": protocol, "from_port": from, "to_port": to, "cidr_ipv4": ipv4, "cidr_ipv6": null},
)

test_https_from_the_internet_passes if {
	doc := fixtures.plan([
		group("web", [entry("tcp", 443, 443, ["0.0.0.0/0"], ["::/0"])], []),
		vpc_rule("http", "tcp", 80, 80, "0.0.0.0/0"),
	])
	count(rule.deny) == 0 with input as doc
}

test_ssh_from_a_private_range_passes if {
	doc := fixtures.plan([
		group("bastion", [entry("tcp", 22, 22, ["10.0.0.0/8"], [])], []),
		vpc_rule("ssh", "tcp", 22, 22, "192.168.0.0/16"),
	])
	count(rule.deny) == 0 with input as doc
}

test_open_egress_passes if {
	egress_rule := fixtures.resource("aws_security_group_rule", "out", {
		"type": "egress", "protocol": "-1", "from_port": 0, "to_port": 0, "cidr_blocks": ["0.0.0.0/0"],
	})
	doc := fixtures.plan([group("web", [], [entry("-1", 0, 0, ["0.0.0.0/0"], [])]), egress_rule])
	count(rule.deny) == 0 with input as doc
}

test_icmp_and_harmless_ranges_pass if {
	doc := fixtures.plan([
		group("ping", [entry("icmp", 8, 0, ["0.0.0.0/0"], [])], []),
		vpc_rule("apps", "tcp", 8000, 8100, "0.0.0.0/0"),
	])
	count(rule.deny) == 0 with input as doc
}

test_ingress_unknown_at_plan_time_is_skipped if {
	unknown := fixtures.with_unknown(fixtures.resource("aws_security_group", "later", {}), {"ingress": true})
	count(rule.deny) == 0 with input as fixtures.plan([unknown])
}

test_inline_ssh_from_anywhere_fails if {
	doc := fixtures.plan([group("bastion", [entry("tcp", 22, 22, ["0.0.0.0/0"], [])], [])])
	rule.deny == {"PAC003 aws_security_group.bastion: ingress from 0.0.0.0/0 to 22 (SSH)"} with input as doc
}

test_standalone_rule_rdp_from_any_ipv6_fails if {
	rdp := fixtures.resource("aws_security_group_rule", "rdp", {
		"type": "ingress", "protocol": "tcp", "from_port": 3389, "to_port": 3389,
		"cidr_blocks": null, "ipv6_cidr_blocks": ["::/0"],
	})
	rule.deny == {"PAC003 aws_security_group_rule.rdp: ingress from ::/0 to 3389 (RDP)"} with input as fixtures.plan([rdp])
}

test_all_protocols_fail_as_all_ports if {
	doc := fixtures.plan([vpc_rule("everything", "-1", null, null, "0.0.0.0/0")])
	expected := "PAC003 aws_vpc_security_group_ingress_rule.everything: ingress from 0.0.0.0/0 to all ports"
	rule.deny == {expected} with input as doc
}

test_wide_port_range_lists_every_sensitive_port if {
	doc := fixtures.plan([vpc_rule("range", "tcp", 3000, 6000, "0.0.0.0/0")])
	expected := concat("", [
		"PAC003 aws_vpc_security_group_ingress_rule.range: ingress from 0.0.0.0/0 to ",
		"3306 (MySQL), 3389 (RDP), 5432 (PostgreSQL), 5900 (VNC)",
	])
	rule.deny == {expected} with input as doc
}

test_protocol_given_as_number_still_fails if {
	doc := fixtures.plan([group("db", [entry("6", 5432, 5432, ["10.0.0.0/8", "0.0.0.0/0"], [])], [])])
	rule.deny == {"PAC003 aws_security_group.db: ingress from 0.0.0.0/0 to 5432 (PostgreSQL)"} with input as doc
}

test_each_open_source_and_resource_is_reported if {
	ssh := entry("tcp", 22, 22, ["0.0.0.0/0"], ["::/0"])
	rdp := entry("udp", 3389, 3389, ["0.0.0.0/0"], [])
	doc := fixtures.plan([group("mixed", [ssh, rdp], []), vpc_rule("redis", "tcp", 6379, 6379, "0.0.0.0/0")])
	rule.deny == {
		"PAC003 aws_security_group.mixed: ingress from 0.0.0.0/0 to 22 (SSH)",
		"PAC003 aws_security_group.mixed: ingress from ::/0 to 22 (SSH)",
		"PAC003 aws_security_group.mixed: ingress from 0.0.0.0/0 to 3389 (RDP)",
		"PAC003 aws_vpc_security_group_ingress_rule.redis: ingress from 0.0.0.0/0 to 6379 (Redis)",
	} with input as doc
}
