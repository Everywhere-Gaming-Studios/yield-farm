from brownie import UniswapV2Pair, UniswapV2Factory, Cosmic, USDT, network, accounts

account = accounts[0]

def deploy_cosmic():
    return Cosmic.deploy({"from": account})

def deploy_usdc():
    return USDT.deploy({"from": account})

def deploy_pair():
    cosmic = deploy_cosmic()
    usdt = deploy_usdc()

    factory = UniswapV2Factory.deploy(account.address, {"from": account})

    pair_address = factory.createPair(cosmic.address, usdt.address)

    print(f"Deployment finished, pair is on address {pair_address}")

def main():
    deploy_pair()
