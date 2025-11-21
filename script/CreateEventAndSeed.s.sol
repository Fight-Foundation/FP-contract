// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script, console2 } from "forge-std/Script.sol";
import { FP1155 } from "src/FP1155.sol";
import { Booster } from "src/Booster.sol";

/**
 * @title CreateEventAndSeed
 * @notice One-shot lifecycle helper: create an event, optionally set a claim deadline, deposit bonuses, seed operator boosts, and optionally resolve fights.
 * @dev All operations assume the broadcaster key has OPERATOR_ROLE on Booster and appropriate admin role on FP1155 (for allowlisting).
 *
 * Environment Variables (all strings unless noted):
 *   PRIVATE_KEY                uint    - Broadcaster private key
 *   FP1155_ADDRESS             address - Deployed FP1155
 *   BOOSTER_ADDRESS            address - Deployed Booster
 *   EVENT_ID                   string  - Identifier (e.g. "UFC_301")
 *   SEASON_ID                  uint    - FP season tokenId
 *   FIGHT_IDS                  string  - Comma-separated fight ids (e.g. "1,2,3")
 *   CLAIM_DEADLINE_OFFSET      uint    - Seconds from now for claim deadline (0 = none)
 *   BONUS_AMOUNTS              string  - Comma amounts per fight (wei), blank or 0 skips (e.g. "100e18,0,500e18")
 *   BOOST_AMOUNTS              string  - Comma amounts for operator boosts (same length as FIGHT_IDS or empty)
 *   BOOST_WINNERS              string  - Comma winners predictions (RED|BLUE|NONE) aligned with BOOST_AMOUNTS
 *   BOOST_METHODS              string  - Comma methods predictions (KNOCKOUT|SUBMISSION|DECISION|NO_CONTEST)
 *   RESOLVE                    bool    - If true, attempt resolution for fights using arrays below
 *   RESULT_WINNERS             string  - Comma actual winners (RED|BLUE|NONE)
 *   RESULT_METHODS             string  - Comma actual methods (KNOCKOUT|SUBMISSION|DECISION|NO_CONTEST)
 *   POINTS_WINNER              string  - Comma uint points per fight (winner only)
 *   POINTS_WINNER_METHOD       string  - Comma uint points per fight (winner+method)
 *   SUM_WINNERS_STAKES         string  - Comma uint sum of winning stakes per fight
 *   WINNING_POOL_TOTAL_SHARES  string  - Comma uint total shares (sum of points * stakes for all winners) per fight
 */
contract CreateEventAndSeed is Script {
    struct ParsedArrays {
        uint256[] fights;
        uint256[] bonusAmts;
        uint256[] boostAmts;
        uint256[] pointsWinner;
        uint256[] pointsWinnerMethod;
        uint256[] sumWinnersStakes;
        uint256[] winningPoolTotalShares;
        Booster.Corner[] boostWinners;
        Booster.WinMethod[] boostMethods;
        Booster.Corner[] resultWinners;
        Booster.WinMethod[] resultMethods;
    }

    function run() external {
        // Load core env
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address fpAddr = vm.envAddress("FP1155_ADDRESS");
        address boosterAddr = vm.envAddress("BOOSTER_ADDRESS");
        string memory eventId = vm.envString("EVENT_ID");
        uint256 seasonId = vm.envUint("SEASON_ID");
        uint256 deadlineOffset = vm.envOr("CLAIM_DEADLINE_OFFSET", uint256(0));
        bool resolve = vm.envOr("RESOLVE", false);

        FP1155 fp = FP1155(fpAddr);
        Booster booster = Booster(boosterAddr);

        vm.startBroadcast(pk);
        address operator = msg.sender;

        console2.log("Operator:", operator);
        console2.log("Event:", eventId);

        // Parse arrays
        ParsedArrays memory P;
        P.fights = _parseUintArray(vm.envString("FIGHT_IDS"));
        if (_hasEnv("BONUS_AMOUNTS")) P.bonusAmts = _parseUintArray(vm.envString("BONUS_AMOUNTS"));
        if (_hasEnv("BOOST_AMOUNTS")) P.boostAmts = _parseUintArray(vm.envString("BOOST_AMOUNTS"));
        if (_hasEnv("BOOST_WINNERS")) P.boostWinners = _parseCornerArray(vm.envString("BOOST_WINNERS"));
        if (_hasEnv("BOOST_METHODS")) P.boostMethods = _parseMethodArray(vm.envString("BOOST_METHODS"));
        if (resolve) {
            P.resultWinners = _parseCornerArray(vm.envString("RESULT_WINNERS"));
            P.resultMethods = _parseMethodArray(vm.envString("RESULT_METHODS"));
            P.pointsWinner = _parseUintArray(vm.envString("POINTS_WINNER"));
            P.pointsWinnerMethod = _parseUintArray(vm.envString("POINTS_WINNER_METHOD"));
            P.sumWinnersStakes = _parseUintArray(vm.envString("SUM_WINNERS_STAKES"));
            P.winningPoolTotalShares = _parseUintArray(vm.envString("WINNING_POOL_TOTAL_SHARES"));
        }

        // Ensure Booster has OPERATOR_ROLE and Booster is allowlisted endpoints
        fp.setTransferAllowlist(operator, true);
        fp.setTransferAllowlist(address(booster), true);

        // Create event (fights are sequential: 1, 2, 3, ..., numFights)
        uint256 numFights = P.fights.length;
        booster.createEvent(eventId, numFights, seasonId, 0);
        console2.log("Created event with", numFights, "fights");

        // Optional deadline
        if (deadlineOffset > 0) {
            uint256 deadline = block.timestamp + deadlineOffset;
            booster.setEventClaimDeadline(eventId, deadline);
            console2.log("Set claim deadline:", deadline);
        }

        // Deposit bonuses
        if (P.bonusAmts.length > 0) {
            for (uint256 i = 0; i < P.fights.length && i < P.bonusAmts.length; i++) {
                uint256 amt = P.bonusAmts[i];
                if (amt == 0) continue;
                booster.depositBonus(eventId, P.fights[i], amt, false);
                console2.log("Deposited bonus", amt, "for fight", P.fights[i]);
            }
        }

        // Seed operator boosts (one boost per fight) if arrays provided
        if (P.boostAmts.length > 0) {
            for (uint256 i = 0; i < P.fights.length && i < P.boostAmts.length; i++) {
                uint256 amt = P.boostAmts[i];
                if (amt == 0) continue;
                Booster.BoostInput[] memory arr = new Booster.BoostInput[](1);
                Booster.Corner winPred = i < P.boostWinners.length ? P.boostWinners[i] : Booster.Corner.RED;
                Booster.WinMethod methodPred =
                    i < P.boostMethods.length ? P.boostMethods[i] : Booster.WinMethod.KNOCKOUT;
                arr[0] = Booster.BoostInput({
                    fightId: P.fights[i], amount: amt, predictedWinner: winPred, predictedMethod: methodPred
                });
                booster.placeBoosts(eventId, arr);
                console2.log("Placed operator boost", amt, "for fight", P.fights[i]);
            }
        }

        // Optionally resolve fights
        if (resolve) {
            for (uint256 i = 0; i < P.fights.length; i++) {
                if (
                    i >= P.resultWinners.length || i >= P.resultMethods.length || i >= P.pointsWinner.length
                        || i >= P.pointsWinnerMethod.length || i >= P.sumWinnersStakes.length
                        || i >= P.winningPoolTotalShares.length
                ) {
                    console2.log("Skip resolve; missing data for fight", P.fights[i]);
                    continue;
                }
                uint256 sumStakes = P.sumWinnersStakes[i];
                uint256 totalShares = P.winningPoolTotalShares[i];
                if (sumStakes == 0 || totalShares == 0) {
                    console2.log("Skip resolve; sumWinnersStakes=0 or winningPoolTotalShares=0 for fight", P.fights[i]);
                    continue;
                }
                booster.submitFightResult(
                    eventId,
                    P.fights[i],
                    P.resultWinners[i],
                    P.resultMethods[i],
                    P.pointsWinner[i],
                    P.pointsWinnerMethod[i],
                    sumStakes,
                    totalShares
                );
                console2.log("Resolved fight", P.fights[i]);
            }
        }

        vm.stopBroadcast();
    }

    // ---------------- Parsing Helpers ----------------

    function _hasEnv(string memory key) internal view returns (bool) {
        // vm.envOr returns default; we treat empty string as missing
        string memory v = vm.envOr(key, string(""));
        return bytes(v).length > 0;
    }

    function _parseUintArray(string memory csv) internal pure returns (uint256[] memory out) {
        bytes memory b = bytes(csv);
        if (b.length == 0) return new uint256[](0);
        uint256 count = 1;
        for (uint256 i = 0; i < b.length; i++) {
            if (b[i] == ",") count++;
        }
        out = new uint256[](count);
        uint256 idx = 0;
        uint256 start = 0;
        for (uint256 i = 0; i <= b.length; i++) {
            if (i == b.length || b[i] == ",") {
                uint256 len = i - start;
                bytes memory slice = new bytes(len);
                for (uint256 j = start; j < i; j++) {
                    slice[j - start] = b[j];
                }
                out[idx++] = _toUint(string(slice));
                start = i + 1;
            }
        }
    }

    function _parseCornerArray(string memory csv) internal pure returns (Booster.Corner[] memory out) {
        string[] memory parts = _split(csv);
        out = new Booster.Corner[](parts.length);
        for (uint256 i = 0; i < parts.length; i++) {
            out[i] = _toCorner(parts[i]);
        }
    }

    function _parseMethodArray(string memory csv) internal pure returns (Booster.WinMethod[] memory out) {
        string[] memory parts = _split(csv);
        out = new Booster.WinMethod[](parts.length);
        for (uint256 i = 0; i < parts.length; i++) {
            out[i] = _toMethod(parts[i]);
        }
    }

    function _split(string memory csv) internal pure returns (string[] memory parts) {
        bytes memory b = bytes(csv);
        if (b.length == 0) return new string[](0);
        uint256 count = 1;
        for (uint256 i = 0; i < b.length; i++) {
            if (b[i] == ",") count++;
        }
        parts = new string[](count);
        uint256 idx = 0;
        uint256 start = 0;
        for (uint256 i = 0; i <= b.length; i++) {
            if (i == b.length || b[i] == ",") {
                uint256 len = i - start;
                bytes memory slice = new bytes(len);
                for (uint256 j = start; j < i; j++) {
                    slice[j - start] = b[j];
                }
                parts[idx++] = string(slice);
                start = i + 1;
            }
        }
    }

    function _toUint(string memory s) internal pure returns (uint256 r) {
        bytes memory b = bytes(s);
        for (uint256 i = 0; i < b.length; i++) {
            uint8 c = uint8(b[i]);
            if (c >= 48 && c <= 57) {
                r = r * 10 + (c - 48);
            } else if (c == 0x20) {
                continue; // ignore spaces
            } else {
                revert("invalid uint");
            }
        }
    }

    function _toCorner(string memory s) internal pure returns (Booster.Corner) {
        bytes32 h = keccak256(abi.encodePacked(_lower(s)));
        if (h == keccak256("red")) return Booster.Corner.RED;
        if (h == keccak256("blue")) return Booster.Corner.BLUE;
        if (h == keccak256("none")) return Booster.Corner.NONE;
        revert("corner");
    }

    function _toMethod(string memory s) internal pure returns (Booster.WinMethod) {
        bytes32 h = keccak256(abi.encodePacked(_lower(s)));
        if (h == keccak256("knockout")) return Booster.WinMethod.KNOCKOUT;
        if (h == keccak256("submission")) return Booster.WinMethod.SUBMISSION;
        if (h == keccak256("decision")) return Booster.WinMethod.DECISION;
        if (h == keccak256("no_contest")) return Booster.WinMethod.NO_CONTEST;
        if (h == keccak256("nocontest")) return Booster.WinMethod.NO_CONTEST;
        revert("method");
    }

    function _lower(string memory s) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        for (uint256 i = 0; i < b.length; i++) {
            uint8 c = uint8(b[i]);
            if (c >= 65 && c <= 90) {
                // A-Z
                b[i] = bytes1(c + 32);
            }
        }
        return string(b);
    }
}
