#!/bin/bash

# Find all directories containing Move.toml and run the command
find . -name 'Move.toml' -execdir sh -c 'echo "Running tests in $(pwd)" && aptos move test --dev' \;
