#!/bin/bash

export LUA_PATH="$PWD/src/?.lua;$PWD/?.lua;$PWD/../build-lua/src/factory/?.lua;;"

# Build project to ensure amm_as_template is available and up to date
# suppress build standard output in order to keep the test output cleaner
echo "Updating amm template ..."
bash scripts/build.sh > /dev/null

# Run tests
echo "Running factory tests ..."
busted test --pattern "_test_factory"
