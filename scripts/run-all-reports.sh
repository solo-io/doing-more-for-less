#!/bin/bash

# Check if file_name argument is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <file_name>"
    exit 1
fi

file_name=$1

# Get the absolute path of the current script
script_dir=$(dirname "$(realpath "$0")")

# Run the latency report script
"$script_dir/latency-report.sh" "$file_name"
if [ $? -ne 0 ]; then
    echo "Failed to generate latency report"
    exit 1
fi

# Run the load generator configuration report script
"$script_dir/loadgen-config-report.sh" "$file_name"
if [ $? -ne 0 ]; then
    echo "Failed to generate load generator configuration report"
    exit 1
fi

# Run the node and pod resource utilization script
"$script_dir/node-pod-resource-utilization.sh" "$file_name"
if [ $? -ne 0 ]; then
    echo "Failed to generate node and pod resource utilization report"
    exit 1
fi

echo "All reports generated successfully with file name prefix: $file_name"
