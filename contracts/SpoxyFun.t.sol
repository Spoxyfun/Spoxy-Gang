// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SpoxyFun} from "../src/SpoxyFun.sol";

/// @notice Minimal stand-in for the Binance Agent ID registry: tracks who
/// holds an Agent ID via a balance mapping.
contract MockAgentIdRegistry {
    mapping(address => uint256) public balanceOf;

    function mint(address to) external {
        balanceOf[to] += 1;
    }
}

contract SpoxyFunTest is Test {
    SpoxyFun nft;
    MockAgentIdRegistry registry;
    address owner = address(0xA11CE);
    address minter = address(0xBEEF);
    address noId = address(0xCAFE);

    string constant BASE = "https://example.com/nft/metadata/";

    function setUp() public {
        registry = new MockAgentIdRegistry();
        vm.prank(owner);
        nft = new SpoxyFun(address(registry), BASE);
        registry.mint(minter);
        vm.deal(minter, 10 ether);
        vm.deal(owner, 1 ether);
        vm.deal(noId, 1 ether);
    }

    function testNameSymbolSupply() public view {
        assertEq(nft.name(), "SpoxyFun");
        assertEq(nft.symbol(), "SPOXY");
        assertEq(nft.MAX_SUPPLY(), 2222);
        assertEq(nft.remaining(), 2222);
    }

    function testMintStartsClosed() public {
        vm.prank(minter);
        vm.expectRevert(SpoxyFun.MintClosed.selector);
        nft.mint{value: 0.0001 ether}();
    }

    // ── Agent ID gate ─────────────────────────────────────────────────

    function testConstructorSetsRegistryAndBaseURI() public view {
        assertEq(nft.agentIdRegistry(), address(registry));
        assertEq(nft.baseURI(), BASE);
    }

    function testConstructorRevertsOnZeroRegistry() public {
        vm.expectRevert(SpoxyFun.InvalidAgentIdRegistry.selector);
        new SpoxyFun(address(0), BASE);
    }

    function testMintRevertsWithoutAgentId() public {
        vm.prank(owner);
        nft.setMintOpen(true);
        vm.prank(noId);
        vm.expectRevert(SpoxyFun.MissingAgentId.selector);
        nft.mint{value: 0.0001 ether}();
        assertEq(nft.totalMinted(), 0);
    }

    function testMintSucceedsWithAgentId() public {
        vm.prank(owner);
        nft.setMintOpen(true);
        vm.prank(minter);
        nft.mint{value: 0.0001 ether}();
        assertEq(nft.totalMinted(), 1);
    }

    // ── Helpers: find minted IDs without assuming any order ──────────

    /// @dev Count how many token IDs 1-2222 `who` owns. With N mints by
    /// one wallet, a count of N proves all minted IDs were distinct and
    /// inside 1-2222.
    function _ownedCount(address who) internal view returns (uint256 count) {
        for (uint256 id = 1; id <= 2222; id++) {
            try nft.ownerOf(id) returns (address o) {
                if (o == who) count++;
            } catch {}
        }
    }

    /// @dev Return the first token ID owned by `who` (reverts if none).
    function _findOwnedId(address who) internal view returns (uint256) {
        for (uint256 id = 1; id <= 2222; id++) {
            try nft.ownerOf(id) returns (address o) {
                if (o == who) return id;
            } catch {}
        }
        revert("none owned");
    }

    function testSingleMintPrice() public view {
        assertEq(nft.MINT_PRICE(), 0.0001 ether);
        assertEq(nft.currentPrice(), 0.0001 ether);
    }

    function testMintedIdsAreWithinRange() public {
        vm.prank(owner);
        nft.setMintOpen(true);

        // 20 random draws, one wallet: every minted ID must land in
        // 1-2222, so the owned count inside that range must be 20.
        for (uint256 i = 0; i < 20; i++) {
            vm.prank(minter);
            nft.mint{value: 0.0001 ether}();
        }
        assertEq(nft.totalMinted(), 20);
        assertEq(_ownedCount(minter), 20);
        assertEq(nft.remaining(), 2222 - 20);
    }

    function testNoDuplicateIdsAcrossBatch() public {
        vm.prank(owner);
        nft.setMintOpen(true);

        // 100 random draws: no ID may repeat, so the wallet must own
        // exactly 100 distinct IDs.
        for (uint256 i = 0; i < 100; i++) {
            vm.prank(minter);
            nft.mint{value: 0.0001 ether}();
        }
        assertEq(nft.totalMinted(), 100);
        assertEq(_ownedCount(minter), 100);
        assertEq(nft.remaining(), 2222 - 100);
    }

    function testMintPriceEnforcedAndOverpaymentRefunded() public {
        vm.prank(owner);
        nft.setMintOpen(true);

        // Underpaying reverts.
        vm.prank(minter);
        vm.expectRevert(
            abi.encodeWithSelector(SpoxyFun.InsufficientPayment.selector, 0.0001 ether, 0.00005 ether)
        );
        nft.mint{value: 0.00005 ether}();

        // Overpayment is refunded; exactly 0.0001 BNB stays in the contract.
        uint256 before = minter.balance;
        vm.prank(minter);
        nft.mint{value: 0.01 ether}();
        assertEq(minter.balance, before - 0.0001 ether);
        assertEq(address(nft).balance, 0.0001 ether);
        assertEq(nft.totalMinted(), 1);
    }

    function testFullMintOutCoversEveryIdOnce() public {
        vm.prank(owner);
        nft.setMintOpen(true);
        for (uint256 i = 0; i < 2222; i++) {
            vm.prank(minter);
            nft.mint{value: 0.0001 ether}();
        }
        assertEq(nft.totalMinted(), 2222);
        assertEq(nft.remaining(), 0);
        // Every ID 1-2222 is owned exactly once (by the single minter).
        assertEq(_ownedCount(minter), 2222);
    }

    function testMaxSupply() public {
        vm.prank(owner);
        nft.setMintOpen(true);
        for (uint256 i = 0; i < 2222; i++) {
            vm.prank(minter);
            nft.mint{value: 0.0001 ether}();
        }
        assertEq(nft.totalMinted(), 2222);
        vm.prank(minter);
        vm.expectRevert(SpoxyFun.MaxSupplyReached.selector);
        nft.mint{value: 0.0001 ether}();
    }

    function testSetMintOpenIsOwnerOnly() public {
        vm.prank(minter);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, minter)
        );
        nft.setMintOpen(true);
        assertFalse(nft.mintOpen());
    }

    function testWithdrawGoesToOwner() public {
        vm.prank(owner);
        nft.setMintOpen(true);
        vm.prank(minter);
        nft.mint{value: 0.0001 ether}();

        uint256 before = owner.balance;
        vm.prank(owner);
        nft.withdraw();
        assertEq(owner.balance, before + 0.0001 ether);
        assertEq(address(nft).balance, 0);
    }

    function testWithdrawIsOwnerOnly() public {
        vm.prank(minter);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, minter)
        );
        nft.withdraw();
    }

    // ── baseURI / tokenURI ────────────────────────────────────────────

    function testTokenUriIsBasePlusIdPlusJson() public {
        vm.prank(owner);
        nft.setMintOpen(true);
        vm.prank(minter);
        nft.mint{value: 0.0001 ether}();
        uint256 tokenId = _findOwnedId(minter);
        assertEq(
            nft.tokenURI(tokenId),
            string.concat(BASE, vm.toString(tokenId), ".json")
        );
    }

    function testTokenUriEmptyWhenBaseEmpty() public {
        vm.prank(owner);
        SpoxyFun empty = new SpoxyFun(address(registry), "");
        vm.prank(owner);
        empty.setMintOpen(true);
        vm.prank(minter);
        empty.mint{value: 0.0001 ether}();
        uint256 tokenId = 0;
        for (uint256 id = 1; id <= 2222; id++) {
            try empty.ownerOf(id) returns (address o) {
                if (o == minter) {
                    tokenId = id;
                    break;
                }
            } catch {}
        }
        assertGt(tokenId, 0);
        assertEq(empty.tokenURI(tokenId), "");
    }

    function testSetBaseUriUpdatesTokenUri() public {
        vm.prank(owner);
        nft.setMintOpen(true);
        vm.prank(minter);
        nft.mint{value: 0.0001 ether}();
        uint256 tokenId = _findOwnedId(minter);

        string memory newBase = "https://new.example/meta/";
        vm.prank(owner);
        nft.setBaseURI(newBase);
        assertEq(nft.baseURI(), newBase);
        assertEq(
            nft.tokenURI(tokenId),
            string.concat(newBase, vm.toString(tokenId), ".json")
        );
    }

    function testSetBaseUriIsOwnerOnly() public {
        vm.prank(minter);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, minter)
        );
        nft.setBaseURI("https://evil.example/");
        assertEq(nft.baseURI(), BASE);
    }
}
