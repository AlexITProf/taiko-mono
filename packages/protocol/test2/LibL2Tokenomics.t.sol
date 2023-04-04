// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {LibL2Tokenomics as T} from "../contracts/L1/libs/LibL2Tokenomics.sol";
import {
    SafeCastUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import {
    LibFixedPointMath as M
} from "../contracts/thirdparty/LibFixedPointMath.sol";

contract TestLibL2Tokenomics is Test {
    using SafeCastUpgradeable for uint256;

    function test1559_2X1XRatio(uint16 rand) public {
        vm.assume(rand != 0);

        uint64 gasExcessMax = (uint(15000000) * 256 * rand).toUint64();
        uint64 gasTarget = (uint(6000000) * rand).toUint64();
        uint64 basefeeInitial = (uint(5000000000) * rand).toUint64();
        uint64 ratio2x1x = 111;
        (uint128 xscale, uint128 yscale) = T.calculateScales({
            xMax: gasExcessMax,
            price: basefeeInitial,
            target: gasTarget,
            ratio2x1x: ratio2x1x
        });

        // basefee should be 0 when gasExcess is 0
        assertEq(T.calculatePrice(xscale, yscale, 0, gasTarget), 0);

        uint64 N = 50;
        // In the [gasExcessMax/2 - 50 * gasTarget, gasExcessMax/2 + 50 * gasTarget]
        // gas range, the ratio2x1x holds, and the gas price is still smaller
        // than uint64.max
        for (
            uint64 l2GasExcess = gasExcessMax / 2 - N * gasTarget;
            l2GasExcess <= gasExcessMax / 2 + N * gasTarget;
            l2GasExcess += gasTarget
        ) {
            uint256 basefee1 = T.calculatePrice(
                xscale,
                yscale,
                l2GasExcess,
                gasTarget
            );
            assertLt(basefee1, type(uint64).max);

            uint256 basefee2 = T.calculatePrice(
                xscale,
                yscale,
                l2GasExcess,
                2 * gasTarget
            );

            assertLt(basefee2, type(uint64).max);

            if (basefee1 != 0) {
                assertEq((basefee2 * 100) / basefee1, ratio2x1x);
            }
        }
    }

    function test1559_SpecalCases(uint16 rand) public {
        vm.assume(rand != 0);

        uint64 gasExcessMax = (uint(15000000) * 256 * rand).toUint64();
        uint64 gasTarget = (uint(6000000) * rand).toUint64();
        uint64 basefeeInitial = (uint(5000000000) * rand).toUint64();
        uint64 ratio2x1x = 111;

        (uint128 xscale, uint128 yscale) = T.calculateScales({
            xMax: gasExcessMax,
            price: basefeeInitial,
            target: gasTarget,
            ratio2x1x: ratio2x1x
        });

        assertEq(T.calculatePrice(xscale, yscale, 0, 0), 0);
        assertEq(T.calculatePrice(xscale, yscale, 0, 1), 0);

        assertGt(
            T.calculatePrice(
                xscale,
                yscale,
                gasExcessMax - gasTarget,
                gasTarget
            ),
            type(uint64).max
        );

        assertGt(
            T.calculatePrice(xscale, yscale, 0, gasExcessMax),
            type(uint64).max
        );

        assertGt(
            T.calculatePrice(
                xscale,
                yscale,
                gasExcessMax / 2,
                gasExcessMax / 2
            ),
            type(uint64).max
        );
    }
}