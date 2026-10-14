# METADATA
# title: "PAC003: no administrative or database port is open to the internet"
# description: >-
#   Security group ingress from 0.0.0.0/0 or ::/0 may reach web ports, but not remote
#   administration (SSH, RDP, VNC, Telnet), databases, caches or the Docker API, and never every
#   port at once. Inline rules, aws_security_group_rule and aws_vpc_security_group_ingress_rule
#   are all checked.
# entrypoint: true
# custom:
#   id: PAC003
#   severity: critical
package terraform.sg_open_ingress

import data.lib.tfplan

sensitive_ports := {
	22: "SSH",
	23: "Telnet",
	1433: "SQL Server",
	1521: "Oracle",
	2375: "Docker API",
	3306: "MySQL",
	3389: "RDP",
	5432: "PostgreSQL",
	5900: "VNC",
	6379: "Redis",
	9200: "Elasticsearch",
	27017: "MongoDB",
}

# Protocol values that mean every protocol and therefore every port.
all_protocols := {"-1", "all"}

# Protocols whose rules carry a port range (TCP and UDP, by name or number).
port_protocols := {"tcp", "udp", "6", "17"}

# Every planned ingress rule, normalised to address, sources, protocol and port range.
ingress contains rule if {
	some group in tfplan.resources_of("aws_security_group")
	some entry in tfplan.list(tfplan.after(group, "ingress", []))
	rule := {
		"address": group.address,
		"sources": array.concat(
			tfplan.list(object.get(entry, "cidr_blocks", [])),
			tfplan.list(object.get(entry, "ipv6_cidr_blocks", [])),
		),
		"protocol": object.get(entry, "protocol", ""),
		"from": object.get(entry, "from_port", 0),
		"to": object.get(entry, "to_port", 0),
	}
}

ingress contains rule if {
	some resource in tfplan.resources_of("aws_security_group_rule")
	tfplan.after(resource, "type", "") == "ingress"
	rule := {
		"address": resource.address,
		"sources": array.concat(
			tfplan.list(tfplan.after(resource, "cidr_blocks", [])),
			tfplan.list(tfplan.after(resource, "ipv6_cidr_blocks", [])),
		),
		"protocol": tfplan.after(resource, "protocol", ""),
		"from": tfplan.after(resource, "from_port", 0),
		"to": tfplan.after(resource, "to_port", 0),
	}
}

ingress contains rule if {
	some resource in tfplan.resources_of("aws_vpc_security_group_ingress_rule")
	rule := {
		"address": resource.address,
		"sources": [source |
			some key in ["cidr_ipv4", "cidr_ipv6"]
			source := tfplan.after(resource, key, "")
			source != ""
		],
		"protocol": tfplan.after(resource, "ip_protocol", ""),
		"from": tfplan.after(resource, "from_port", 0),
		"to": tfplan.after(resource, "to_port", 0),
	}
}

deny contains msg if {
	some rule in ingress
	protocol(rule) in all_protocols
	some source in open_sources(rule)
	msg := $"PAC003 {rule.address}: ingress from {source} to all ports"
}

deny contains msg if {
	some rule in ingress
	protocol(rule) in port_protocols
	ports := [$"{port} ({name})" | some port, name in sensitive_ports; rule.from <= port; port <= rule.to]
	count(ports) > 0
	some source in open_sources(rule)
	msg := $"PAC003 {rule.address}: ingress from {source} to {concat(", ", ports)}"
}

# Sources of a rule that cover the whole internet: 0.0.0.0/0, ::/0 or any other /0.
open_sources(rule) := [source | some source in rule.sources; endswith(source, "/0")]

# The rule's protocol as a lowercase string, whatever type the plan used.
protocol(rule) := lower(sprintf("%v", [rule.protocol]))
