#!/bin/bash

# Check if file_name argument is provided
if [ -z "$1" ]; then
    echo "Error: file_name argument is required"
    exit 1
fi

file_name=$1

# Get current date
current_date=$(date +"%m-%d-%Y")

# Define the output directory and files
output_dir="out/$current_date"
output_file="$output_dir/$file_name.md"
table_file="$output_dir/$file_name-latency-summary-table.md"

# Define label selectors for pods
label_selectors=("app=vegeta1" "app=vegeta2")  # Modify this array as per your requirement

# Create the output directory if it does not exist
mkdir -p $output_dir

# Clear the output files if they exist
> $output_file
> $table_file

# Start code block
echo '```' >> "$output_file"

# Define the range of namespaces
start_namespace=1
end_namespace=25

# Define an array of namespaces from start_namespace to end_namespace
namespaces=()

for ((i=start_namespace; i<=end_namespace; i++)); do
    namespaces+=("ns-$i")
done

# Initialize variables for calculating average latencies
total_p50=0
total_p90=0
total_p95=0
total_tests=0

# Create the summary table header
echo "| Namespace | P50 (ms) | P90 (ms) | P95 (ms) | Meets Expectations | Completed Without Errors |" >> "$table_file"
echo "|-----------|----------|----------|----------|--------------------|--------------------------|" >> "$table_file"

# Loop through each namespace
for namespace in "${namespaces[@]}"; do
    echo "Namespace: $namespace" >> "$output_file"
    
    # Loop through each label selector
    for label_selector in "${label_selectors[@]}"; do
        echo "Label Selector: $label_selector" >> "$output_file"

        # Get the list of pods in the namespace with the specified label selector
        pods=$(kubectl -n "$namespace" get pods --selector="$label_selector" -o=jsonpath='{.items[*].metadata.name}')
        
        # Loop through each pod in the namespace
        for pod in $pods; do
            echo "Pod: $pod" >> "$output_file"

            # Get the most recent log of the pod in the namespace and append to the output file
            kubectl -n "$namespace" logs -c vegeta --tail 10 "$pod" >> "$output_file" 2>&1
            echo "" >> "$output_file"  # Add empty line after logs

            # Extract the latencies from the logs
            latencies=$(kubectl -n "$namespace" logs -c vegeta --tail 10 "$pod" | grep "Latencies")
            echo "Latencies line: $latencies"  # Debugging output

            if [ -z "$latencies" ]; then
                echo "No latencies found for pod $pod in namespace $namespace" >> "$output_file"
                continue
            fi

            # Extract the latency values using regex
            if [[ $latencies =~ ([0-9.]+)ms,\ ([0-9.]+)ms,\ ([0-9.]+)ms,\ ([0-9.]+)ms,\ ([0-9.]+)ms,\ ([0-9.]+)ms,\ ([0-9.]+)ms ]]; then
                p50=${BASH_REMATCH[3]}
                p90=${BASH_REMATCH[4]}
                p95=${BASH_REMATCH[5]}
            else
                echo "Failed to parse latencies for pod $pod in namespace $namespace" >> "$output_file"
                continue
            fi

            # Remove 'ms' suffix and convert to float
            p50=$(echo $p50 | sed 's/ms//')
            p90=$(echo $p90 | sed 's/ms//')
            p95=$(echo $p95 | sed 's/ms//')

            # Check if the test meets expectations
            if (( $(echo "$p50 < 10" | bc -l) )) && (( $(echo "$p95 < 15" | bc -l) )); then
                meets_expectations="Yes"
            else
                meets_expectations="No"
            fi

            # Check if the test completed without errors
            error_set=$(kubectl -n "$namespace" logs -c vegeta --tail 10 "$pod" | grep "Error Set: ")
            if [ -z "$error_set" ]; then
                completed_without_errors="Yes"
            else
                completed_without_errors="No"
            fi

            # Append the results to the summary table
            echo "| $namespace | $p50 | $p90 | $p95 | $meets_expectations | $completed_without_errors |" >> "$table_file"

            # Update the total latencies for averaging
            total_p50=$(echo "$total_p50 + $p50" | bc)
            total_p90=$(echo "$total_p90 + $p90" | bc)
            total_p95=$(echo "$total_p95 + $p95" | bc)
            total_tests=$((total_tests + 1))
        done
    done
done

# Calculate the average latencies
average_p50=$(echo "scale=3; $total_p50 / $total_tests" | bc)
average_p90=$(echo "scale=3; $total_p90 / $total_tests" | bc)
average_p95=$(echo "scale=3; $total_p95 / $total_tests" | bc)

# Append the average latencies to the summary table
echo "" >> "$table_file"
echo "### Average Latencies" >> "$table_file"
echo "| Average P50 (ms) | Average P90 (ms) | Average P95 (ms) |" >> "$table_file"
echo "|------------------|------------------|------------------|" >> "$table_file"
echo "| $average_p50 | $average_p90 | $average_p95 |" >> "$table_file"

# End code block
echo '```' >> "$output_file"

echo "Output written to $output_file and $table_file"
