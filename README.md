# solidity2smartpy
solidity to SmartPy translator
VERY EXPERIMENTAL. Generated code slightly tested for correctness in https://smartpy.io/demo/#

## recommended software requirements

    # install nvm https://github.com/nvm-sh/nvm 
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.34.0/install.sh | bash
    source ~/.bashrc
    # node install
    nvm i 6.6
    npm i -g iced-coffee-script

## how to use
NOTE there is no cli tool for now. But workaround is present.

    # no cli tool for now
    # clone this repo (one time)
    git clone https://github.com/vird/solidity2smartpy
    cd solidity2smartpy
    # how to use
    ./test_translate.coffee <contract.sol>
