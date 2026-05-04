#!/bin/bash

echo "=== Clearing Hive Database Locks ==="

# Get the app data directory (this is a simplified version for Windows)
# In a real scenario, this would use the actual app data path
HIVE_DIR="$HOME/AppData/Documents/navi_data"

if [ -d "$HIVE_DIR" ]; then
    echo "Found Hive directory: $HIVE_DIR"
    echo "Removing lock files..."

    # Remove all .lock files
    find "$HIVE_DIR" -name "*.lock" -type f -delete

    echo "Lock files cleared successfully!"
else
    echo "Hive directory not found at $HIVE_DIR"
    echo "This might be normal if the app hasn't run yet."
fi

echo "=== Done ==="