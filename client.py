import os
from web3 import Web3
from web3.middleware import geth_poa_middleware

import deploy


# Set up web3 connection
provider_url = os.environ.get("CELO_PROVIDER_URL")
w3 = Web3(Web3.HTTPProvider(provider_url))
assert w3.is_connected(), "Not connected to a Celo node"

# Add PoA middleware to web3.py instance
w3.middleware_onion.inject(geth_poa_middleware, layer=0)


abi = deploy.abi
contract_address =  deploy.contract_address
private_key = deploy.private_key
deployer = deploy.deployer


contract = w3.eth.contract(address=contract_address, abi=abi)


def build_transaction(fn, *args, **kwargs):
    nonce = w3.eth.get_transaction_count(deployer)
    txn = fn.build_transaction(
        {"from": deployer, "gas": 1500000, "nonce": nonce, **kwargs}
    )
    signed_txn = w3.eth.account.sign_transaction(txn, private_key)
    return signed_txn


def create_loan(loan_amount, collateral_amount, collateral_token):
    create_loan_fn = contract.functions.createLoan(
        loan_amount, collateral_amount, collateral_token
    )
    signed_txn = build_transaction(create_loan_fn)
    txn_hash = w3.eth.send_raw_transaction(signed_txn.rawTransaction)
    return txn_hash


def repay_loan(amount):
    repay_loan_fn = contract.functions.repayLoan(amount)
    signed_txn = build_transaction(repay_loan_fn)
    txn_hash = w3.eth.send_raw_transaction(signed_txn.rawTransaction)
    return txn_hash


def liquidate_loan(borrower):
    liquidate_loan_fn = contract.functions.liquidateLoan(borrower)
    signed_txn = build_transaction(liquidate_loan_fn)
    txn_hash = w3.eth.send_raw_transaction(signed_txn.rawTransaction)
    return txn_hash


def get_collateral_value(collateral_amount, collateral_token):
    collateral_value = contract.functions.getCollateralValue(
        collateral_amount, collateral_token
    ).call()
    return collateral_value


def set_price_oracle(new_oracle):
    set_price_oracle_fn = contract.functions.setPriceOracle(new_oracle)
    signed_txn = build_transaction(set_price_oracle_fn)
    txn_hash = w3.eth.send_raw_transaction(signed_txn.rawTransaction)
    return txn_hash


# Create Loan

loan_amount = 1000
collateral_amount = 2000
collateral_token = "0x8BdDeC1b7841bF9eb680bE911bd22051f6a00815"  # Replace with the actual token address

txn_hash = create_loan(loan_amount, collateral_amount, collateral_token)
receipt = w3.eth.wait_for_transaction_receipt(txn_hash)
print(receipt)
