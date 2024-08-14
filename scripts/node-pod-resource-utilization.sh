#!/bin/bash

# Check if file_name argument is provided
if [ -z "$1" ]; then
    echo "Error: file_name argument is required"
    exit 1
fi

file_name=$1

# Get current date
current_date=$(date +"%m-%d-%Y")

# Define the output directory and file
output_dir="out/$current_date"
output_file="$output_dir/$file_name-node-pod-utilization.md"

# Create the output directory if it does not exist
mkdir -p $output_dir

# Clear the output file if it exists
> $output_file

# Write the header for the output file
echo "| Node | Load Gen Node | Node CPU Usage | Node Memory Usage | Pod | Pod Namespace | Container | Container CPU Usage | Container Memory Usage |" >> $output_file
echo "|------|---------------|----------------|-------------------|-----|---------------|-----------|---------------------|------------------------|" >> $output_file

# Variables for calculating averages
total_cpu_loadgen=0
total_mem_loadgen=0
total_cpu_workload=0
total_mem_workload=0
count_loadgen=0
count_workload=0

# Get all nodes
nodes=$(kubectl get nodes --no-headers -o custom-columns=NAME:.metadata.name)

# Get all namespaces
namespaces=$(kubectl get namespaces -o jsonpath="{.items[*].metadata.name}")

# Loop through each node
for node in $nodes; do
    # Check if the node has the label "node=loadgen"
    if kubectl get node $node --no-headers -L node | grep -q "loadgen"; then
        loadgen="true"
        count_loadgen=$((count_loadgen+1))
    else
        loadgen="false"
        count_workload=$((count_workload+1))
    fi

    # Get node CPU and memory utilization
    node_cpu=$(kubectl top node $node --no-headers | awk '{print $3}' | sed 's/%//')
    node_mem=$(kubectl top node $node --no-headers | awk '{print $5}' | sed 's/%//')

    # Accumulate the total CPU and memory usage
    if [ "$loadgen" == "true" ]; then
        total_cpu_loadgen=$((total_cpu_loadgen + node_cpu))
        total_mem_loadgen=$((total_mem_loadgen + node_mem))
    else
        total_cpu_workload=$((total_cpu_workload + node_cpu))
        total_mem_workload=$((total_mem_workload + node_mem))
    fi
    
    # Loop through each namespace
    for namespace in $namespaces; do
        # Get the list of pods running on the node
        pods=$(kubectl get pods -n $namespace --field-selector spec.nodeName=$node -o jsonpath="{.items[*].metadata.name}")
        for pod in $pods; do
            # Get container-specific utilization
            pod_utilization=$(kubectl top pod $pod -n $namespace --containers --no-headers)
            while read -r line; do
                container=$(echo $line | awk '{print $2}')
                container_cpu=$(echo $line | awk '{print $3}')
                container_mem=$(echo $line | awk '{print $4}')
                echo "| $node | $loadgen | ${node_cpu}% | ${node_mem}% | $pod | $namespace | $container | $container_cpu | $container_mem |" >> $output_file
            done <<< "$pod_utilization"
        done
    done
done

# Calculate the average CPU and memory utilization
avg_cpu_loadgen=0
avg_mem_loadgen=0
avg_cpu_workload=0
avg_mem_workload=0

if [ $count_loadgen -gt 0 ]; then
    avg_cpu_loadgen=$(echo "scale=2; $total_cpu_loadgen / $count_loadgen" | bc)
    avg_mem_loadgen=$(echo "scale=2; $total_mem_loadgen / $count_loadgen" | bc)
fi

if [ $count_workload -gt 0 ]; then
    avg_cpu_workload=$(echo "scale=2; $total_cpu_workload / $count_workload" | bc)
    avg_mem_workload=$(echo "scale=2; $total_mem_workload / $count_workload" | bc)
fi

# Write the averages to the output file
echo "" >> $output_file
echo "### Average Node CPU and Memory Utilization" >> $output_file
echo "| Node Type | Number of Nodes | Average CPU Usage (%) | Average Memory Usage (%) |" >> $output_file
echo "|-----------|-----------------|------------------------|-------------------------|" >> $output_file
echo "| Load Gen  | $count_loadgen  | $avg_cpu_loadgen       | $avg_mem_loadgen        |" >> $output_file
echo "| Workload  | $count_workload | $avg_cpu_workload      | $avg_mem_workload       |" >> $output_file

echo "Output written to $output_file"
