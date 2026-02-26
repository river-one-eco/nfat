// SPDX-FileCopyrightText: © 2026 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.24;

import { ERC721 } from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

interface GemLike {
    function transferFrom(address from, address to, uint256 amount) external;
    function transfer(address to, uint256 amount) external;
}

interface IdentityNetworkLike {
    function isMember(address usr) external view returns (bool);
}

contract NFATFacility is ERC721 {

    mapping(address usr       => uint256 allowed) public wards;
    mapping(address usr       => uint256 allowed) public buds;     // Operator(s)
    mapping(address usr       => uint256 allowed) public cops;     // Freezers
    mapping(address depositor => uint256 amount)  public deposits; 
    mapping(uint256 tokenId   => uint256 amount)  public funded;
    bool                public stopped;
    IdentityNetworkLike public identityNetwork;

    GemLike public immutable gem;        // Underlying asset
    address public immutable recipient;  // Destination of funds claimed by the operator

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Kiss(address indexed usr);
    event Diss(address indexed usr);
    event AddFreezer(address indexed usr);
    event RemoveFreezer(address indexed usr);
    event Stop();
    event Start();
    event File(bytes32 indexed what, address data);
    event Subscribe(address indexed depositor, uint256 amount);
    event Withdraw(address indexed depositor, uint256 amount);
    event Issue(address indexed target, uint256 indexed tokenId, uint256 amount);
    event Fund(uint256 indexed tokenId, address indexed funder, uint256 amount);
    event Redeem(uint256 indexed tokenId, uint256 amount);
    event Rescue(address indexed token, address indexed to, uint256 amount);
    event RescueDeposit(address indexed depositor, address indexed to, uint256 amount);
    event RescueFunded(uint256 indexed tokenId, address indexed to, uint256 amount);

    // --- Modifiers ---

    modifier auth() {
        require(wards[msg.sender] == 1, "NFATFacility/not-authorized");
        _;
    }

    modifier toll() {
        require(buds[msg.sender] == 1 || wards[msg.sender] == 1, "NFATFacility/not-operator");
        _;
    }

    modifier cop() {
        require(cops[msg.sender] == 1 || wards[msg.sender] == 1, "NFATFacility/not-freezer");
        _;
    }

    modifier notStopped() {
        require(!stopped, "NFATFacility/stopped");
        _;
    }

    // --- Constructor ---

    constructor(address gem_, address recipient_, string memory name_, string memory symbol_)
        ERC721(name_, symbol_)
    {
        gem = GemLike(gem_);
        recipient = recipient_;
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Access Control Functions ---

    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    function kiss(address usr) external auth {
        buds[usr] = 1;
        emit Kiss(usr);
    }

    function diss(address usr) external auth {
        buds[usr] = 0;
        emit Diss(usr);
    }

    function addFreezer(address usr) external auth {
        cops[usr] = 1;
        emit AddFreezer(usr);
    }

    function removeFreezer(address usr) external auth {
        cops[usr] = 0;
        emit RemoveFreezer(usr);
    }

    function stop() external cop {
        stopped = true;
        emit Stop();
    }

    function start() external auth {
        stopped = false;
        emit Start();
    }

    function file(bytes32 what, address data) external auth {
        if (what == "identityNetwork") identityNetwork = IdentityNetworkLike(data);
        else revert("NFATFacility/file-unrecognized-param");
        emit File(what, data);
    }

    // --- Queue Functions ---

    function subscribe(uint256 amount) external {
        require(amount > 0, "NFATFacility/zero-amount");
        deposits[msg.sender] += amount;
        gem.transferFrom(msg.sender, address(this), amount);
        emit Subscribe(msg.sender, amount);
    }

    function withdraw(uint256 amount) external {
        require(amount > 0, "NFATFacility/zero-amount");
        require(deposits[msg.sender] >= amount, "NFATFacility/insufficient-deposits");
        unchecked { deposits[msg.sender] -= amount; }
        gem.transfer(msg.sender, amount);
        emit Withdraw(msg.sender, amount);
    }

    // Note: amount = 0 is allowed (mint NFAT without moving funds)
    function issue(address target, uint256 tokenId, uint256 amount) external toll notStopped {
        require(tokenId != 0, "NFATFacility/token-id-zero");
        require(deposits[target] >= amount, "NFATFacility/insufficient-deposits");
        unchecked { deposits[target] -= amount; }
        _mint(target, tokenId); // identity network check in _update
        if (amount > 0) gem.transfer(recipient, amount);
        emit Issue(target, tokenId, amount);
    }

    // --- Redeem Functions ---

    // Note: the recipient of a transferred NFAT is assumed aware of current and future planned funding, including potential front-running
    function fund(uint256 tokenId, uint256 amount) external {
        require(amount > 0, "NFATFacility/zero-amount");
        require(_ownerOf(tokenId) != address(0), "NFATFacility/invalid-token");
        funded[tokenId] += amount;
        gem.transferFrom(msg.sender, address(this), amount);
        emit Fund(tokenId, msg.sender, amount);
    }

    function redeem(uint256 tokenId, uint256 amount) external {
        require(amount > 0, "NFATFacility/zero-amount");
        require(funded[tokenId] >= amount, "NFATFacility/insufficient-funded");
        require(msg.sender == _ownerOf(tokenId), "NFATFacility/not-owner");
        require(address(identityNetwork) == address(0) || identityNetwork.isMember(msg.sender), "NFATFacility/not-member");
        unchecked { funded[tokenId] -= amount; }
        gem.transfer(msg.sender, amount);
        emit Redeem(tokenId, amount);
    }

    // --- ERC-721 Overrides ---

    // Note: `to` is guaranteed non-zero (OZ reverts before _update when to == address(0), and _burn is never invoked)
    function _update(address to, uint256 tokenId, address auth_) internal override returns (address) {
        require(
            address(identityNetwork) == address(0) || identityNetwork.isMember(to),
            "NFATFacility/not-member"
        );
        return super._update(to, tokenId, auth_);
    }

    // --- Rescue Functions ---

    // Note: In order to rescue gem balances tracked by the `deposits` or `funded` mappings, prefer using rescueDeposit/rescueFunded over this function
    function rescue(address token, address to, uint256 amount) external auth {
        GemLike(token).transfer(to, amount);
        emit Rescue(token, to, amount);
    }

    function rescueDeposit(address depositor, address to, uint256 amount) external auth {
        require(deposits[depositor] >= amount, "NFATFacility/insufficient-deposits");
        unchecked { deposits[depositor] -= amount; }
        gem.transfer(to, amount);
        emit RescueDeposit(depositor, to, amount);
    }

    function rescueFunded(uint256 tokenId, address to, uint256 amount) external auth {
        require(funded[tokenId] >= amount, "NFATFacility/insufficient-funded");
        unchecked { funded[tokenId] -= amount; }
        gem.transfer(to, amount);
        emit RescueFunded(tokenId, to, amount);
    }
}
