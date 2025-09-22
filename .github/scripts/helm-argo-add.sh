#!/bin/bash
set -e

# Find all Helm chart sources in Argo CD Application manifests
# and add the corresponding Helm repositories if they are not already added.
# This script assumes that 'helm' and 'yq' are installed and available in the PATH.
crawl=$(for file in $(find kubernetes/applications -type f -maxdepth 1); do 
    if yq e 'explode(.) | has("*chartVersion*")' "$file" > /dev/null 2>&1; then
        yq e 'explode(.)' "$file" | yq e '.spec.sources[]? | select(.repoURL and .chart and .targetRevision) | [.repoURL, .chart, .targetRevision] | join(",")' 
    fi
done | sort -u)

echo "$crawl" | while IFS=',' read -r repo_url chart target_revision; do
	# Get the list of currently added Helm repo URLs
	repo_urls=$(helm repo list -oyaml | yq '.[].url')
	
	# Only process valid HTTP(S) URLs
	if [[ "$repo_url" == "https://"* ]]; then
		# Check if the repo URL is already added
		if [[ ! "$repo_urls" == *"${repo_url}"* ]]; then 
			helm repo add "${chart}" "${repo_url}"
		else
			continue
		fi
	else # Skip over any oci:// or empty URLs
		continue
	fi
done

# Update Helm repos
helm repo update
