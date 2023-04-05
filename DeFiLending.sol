// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "node_modules/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "node_modules/@openzeppelin/contracts/access/Ownable.sol";
import "node_modules/@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract DeFiLending is Ownable {
    using SafeERC20 for IERC20;

    uint256 public constant COLLATERAL_RATIO = 150;
    uint256 public constant LIQUIDATION_DISCOUNT = 90;

    struct Loan {
        uint256 amount;
        uint256 collateralAmount;
        address collateralToken;
        uint256 lastInterestUpdate;
    }

    IERC20 public lendingToken;
    AggregatorV3Interface public priceOracle;
    mapping(address => Loan) public loans;

    event LoanCreated(address indexed borrower, uint256 amount);
    event LoanRepaid(address indexed borrower, uint256 amount);
    event LoanLiquidated(address indexed borrower, uint256 amount);

    constructor(IERC20 _lendingToken, AggregatorV3Interface _priceOracle) {
        lendingToken = _lendingToken;
        priceOracle = _priceOracle;
    }

    function createLoan(
        uint256 loanAmount,
        uint256 collateralAmount,
        IERC20 collateralToken
    ) external {
        require(loanAmount > 0, "Invalid loan amount");
        require(collateralAmount > 0, "Invalid collateral amount");
        require(loans[msg.sender].amount == 0, "Existing loan");

        uint256 collateralValue = getCollateralValue(
            collateralAmount,
            collateralToken
        );
        uint256 minCollateralValue = (loanAmount * COLLATERAL_RATIO) / 100;

        require(
            collateralValue >= minCollateralValue,
            "Insufficient collateral"
        );

        collateralToken.safeTransferFrom(
            msg.sender,
            address(this),
            collateralAmount
        );
        lendingToken.safeTransfer(msg.sender, loanAmount);

        loans[msg.sender] = Loan({
            amount: loanAmount,
            collateralAmount: collateralAmount,
            collateralToken: address(collateralToken),
            lastInterestUpdate: block.timestamp
        });

        emit LoanCreated(msg.sender, loanAmount);
    }

    function repayLoan(uint256 amount) external {
        Loan storage loan = loans[msg.sender];
        require(amount > 0, "Invalid amount");
        require(loan.amount >= amount, "Loan amount exceeded");

        lendingToken.safeTransferFrom(msg.sender, address(this), amount);

        if (loan.amount == amount) {
            IERC20(loan.collateralToken).safeTransfer(
                msg.sender,
                loan.collateralAmount
            );
            delete loans[msg.sender];
        } else {
            loan.amount -= amount;
        }

        emit LoanRepaid(msg.sender, amount);
    }

    function liquidateLoan(address borrower) external {
        Loan storage loan = loans[borrower];
        require(loan.amount > 0, "No active loan");

        uint256 collateralValue = getCollateralValue(
            loan.collateralAmount,
            IERC20(loan.collateralToken)
        );
        uint256 minCollateralValue = (loan.amount * COLLATERAL_RATIO) / 100;

        require(
            collateralValue < minCollateralValue,
            "Loan not undercollateralized"
        );

        uint256 discountedCollateralAmount = (loan.collateralAmount *
            loan.amount *
            LIQUIDATION_DISCOUNT) / 100;

        lendingToken.safeTransferFrom(msg.sender, address(this), loan.amount);
        IERC20(loan.collateralToken).safeTransfer(
            msg.sender,
            discountedCollateralAmount
        );

        delete loans[borrower];

        emit LoanLiquidated(borrower, loan.amount);
    }

    function getCollateralValue(
        uint256 collateralAmount,
        IERC20 collateralToken
    ) public view returns (uint256) {
        address tokenAddress = address(collateralToken);
        require(
            tokenAddress != address(lendingToken),
            "Collateral cannot be lending token"
        );

        AggregatorV3Interface collateralPriceOracle = AggregatorV3Interface(
            tokenAddress
        );

        (, int256 collateralPrice, , , ) = collateralPriceOracle
            .latestRoundData();
        require(collateralPrice > 0, "Invalid collateral price");

        return
            (uint256(collateralPrice) * collateralAmount) /
            (10 ** collateralPriceOracle.decimals());
    }

    function setPriceOracle(
        AggregatorV3Interface newOracle
    ) external onlyOwner {
        priceOracle = newOracle;
    }
}
