#!/bin/bash

# Recreate build directories
rm -rf ./build
rm -rf ./build-lua

mkdir -p ./build
mkdir -p ./build-lua

# build teal
cyan build -u
# Build amm
cd build-lua
mv ./amm/main.lua ./amm.lua
amalg.lua -s amm.lua -o ../build/amm.lua \
    amm.amm-handlers \
    amm.pool.burn amm.pool.cancel amm.pool.globals amm.pool.pool amm.pool.provide amm.pool.refund amm.pool.swap \
    amm.token.balance amm.token.credit_notice amm.token.globals amm.token.token amm.token.transfer \
    utils.assertions utils.tl-bint utils.bintmath utils.tl-utils utils.patterns utils.output utils.responses utils.forward-tags \
    subscriptions.subscribable amm.state

# Create template file
cd ../build
{
  echo 'AMM_PROCESS_CODE = [===['
  cat amm.lua
  echo ']===] 

return AMM_PROCESS_CODE'
} > amm_as_template.lua

# add template file to factory sources for building
cp amm_as_template.lua ../build-lua/amm_as_template.lua

# Build factory
cd ../build-lua
mv ./factory/factory.lua ./factory.lua
amalg.lua -s factory.lua -o ../build/factory.lua \
    amm_as_template  \
    factory.factory_lib factory.globals \
    utils.tl-utils utils.assertions utils.tl-bint utils.responses utils.reset-modules-code utils.set-dexi-token-code
