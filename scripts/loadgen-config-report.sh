#!/bin/bash

# Check if file_name argument is provided
if [ -z "$1" ]; then
    echo "Error: file_name argument is required"
    exit 1
fi

file_name=$1

# Get current date
current_date=$(date +"%m-%d-%Y")

# Output directory
output_dir="out/$current_date"
output_file="$output_dir/$file_name-load-gen-config.md"

# Create the output directory if it does not exist
mkdir -p $output_dir

# Clear the output file if it exists
> $output_file

# Write the header for the output file
echo "| Name | Namespace | Node | REQUESTS_PER_SECOND | DURATION | CONNECTIONS | MAX_CONNECTIONS |" >> $output_file
echo "|------|-----------|------|---------------------|----------|-------------|-----------------|" >> $output_file

# Get all namespaces
namespaces=$(kubectl get namespaces -o jsonpath="{.items[*].metadata.name}")

# Loop through each namespace
for namespace in $namespaces; do
    # Get the list of vegeta1 pods in the namespace
    pods=$(kubectl get pods -n $namespace -l app=vegeta1 -o jsonpath="{.items[*].metadata.name}")
    
    for pod in $pods; do
        # Get the node the pod is running on
        node=$(kubectl get pod $pod -n $namespace -o jsonpath="{.spec.nodeName}")

        # Get the environment variables for the container named "vegeta"
        env_vars=$(kubectl get pod $pod -n $namespace -o json | jq -r '.spec.containers[] | select(.name == "vegeta") | .env[] | select(.name | test("REQUESTS_PER_SECOND|DURATION|CONNECTIONS|MAX_CONNECTIONS")) | [.name, .value] | @tsv' | awk 'BEGIN {ORS="; "} {print $1 "=" $2}')
        
        requests_per_second=$(echo $env_vars | awk -F'REQUESTS_PER_SECOND=' '{print $2}' | awk -F';' '{print $1}')
        duration=$(echo $env_vars | awk -F'DURATION=' '{print $2}' | awk -F';' '{print $1}')
        connections=$(echo $env_vars | awk -F'CONNECTIONS=' '{print $2}' | awk -F';' '{print $1}')
        max_connections=$(echo $env_vars | awk -F'MAX_CONNECTIONS=' '{print $2}' | awk -F';' '{print $1}')

        # Write the pod details to the output file
        echo "| $pod | $namespace | $node | $requests_per_second | $duration | $connections | $max_connections |" >> $output_file
    done
done

echo "Output written to $output_file"
