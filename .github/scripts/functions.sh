# Scrape all namespaces from kubernetes YAML files
function get_namespaces() {
	for file in $(find kubernetes/ -name '*.yaml' -type f); do
		cat ${file} | yq e 'explode(.)' |
		grep 'namespace:' | awk '{print $2}'
	done | tr -d '"' | sed 's/namespace\://g' | sort | uniq | xargs
}