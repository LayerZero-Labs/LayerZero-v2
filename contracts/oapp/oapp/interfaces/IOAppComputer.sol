// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { IOAppComputerReduce } from "./IOAppComputerReduce.sol";
import { IOAppComputerMap } from "./IOAppComputerMap.sol";

interface IOAppComputer is IOAppComputerMap, IOAppComputerReduce {}
