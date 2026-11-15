// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {SpoxyFun} from "./SpoxyFun.sol";

contract MockAgentIdRegistry {
    mapping(address => uint256) public balanceOf;
    function mint(address to) external { balanceOf[to] += 1; }
}

contract SpoxyFunTest is Test {
    SpoxyFun nft;
    MockAgentIdRegistry registry;
    address owner = address(0xA11CE);
    address agentWallet = address(0xBEEF);
    address paidWallet = address(0xCAFE);
    string constant BASE = "https://example.com/nft/metadata/";

    function setUp() public {
        registry = new MockAgentIdRegistry();
        vm.prank(owner);
        nft = new SpoxyFun(address(registry), BASE);
        registry.mint(agentWallet);
        vm.deal(agentWallet, 2 ether);
        vm.deal(paidWallet, 2 ether);
        vm.deal(owner, 1 ether);
    }

    function _open() internal {
        vm.prank(owner);
        nft.setMintOpen(true);
    }

    function testConstantsAndStartsClosed() public view {
        assertEq(nft.MAX_SUPPLY(), 2222);
        assertEq(nft.FREE_SUPPLY(), 800);
        assertEq(nft.FREE_PER_WALLET(), 3);
        assertEq(nft.MINT_PRICE(), 0.001 ether);
        assertFalse(nft.mintOpen());
    }

    function testPaidMintImmediatelyWithoutAgentId() public {
        _open();
        vm.prank(paidWallet);
        nft.mint{value: 0.001 ether}();
        assertEq(nft.totalMinted(), 1);
        assertEq(nft.freeMinted(), 0);
        assertEq(address(nft).balance, 0.001 ether);
    }

    function testFreeMintRequiresAgentId() public {
        _open();
        vm.prank(paidWallet);
        vm.expectRevert(SpoxyFun.MissingAgentId.selector);
        nft.freeMint();
    }

    function testFreeMintThreeTimesThenWalletCap() public {
        _open();
        for (uint256 i; i < 3; ++i) {
            vm.prank(agentWallet);
            nft.freeMint();
        }
        assertEq(nft.freeMintedByWallet(agentWallet), 3);
        assertEq(nft.freeMinted(), 3);
        vm.prank(agentWallet);
        vm.expectRevert(SpoxyFun.FreeWalletLimitReached.selector);
        nft.freeMint();
    }

    function testPaidMintUnderpaymentRevertsAndOverpaymentRefunded() public {
        _open();
        vm.prank(paidWallet);
        vm.expectRevert(abi.encodeWithSelector(SpoxyFun.InsufficientPayment.selector, 0.001 ether, 0.0009 ether));
        nft.mint{value: 0.0009 ether}();

        uint256 beforeBalance = paidWallet.balance;
        vm.prank(paidWallet);
        nft.mint{value: 0.01 ether}();
        assertEq(paidWallet.balance, beforeBalance - 0.001 ether);
        assertEq(address(nft).balance, 0.001 ether);
    }

    function testFreeAndPaidShareSupplyAndUniqueIds() public {
        _open();
        for (uint256 i; i < 3; ++i) {
            vm.prank(agentWallet);
            nft.freeMint();
        }
        vm.prank(paidWallet);
        nft.mint{value: 0.001 ether}();
        assertEq(nft.totalMinted(), 4);
        assertEq(nft.remaining(), 2218);
        assertEq(nft.freeMinted(), 3);
    }

    function testMintClosedForBothMethods() public {
        vm.prank(agentWallet);
        vm.expectRevert(SpoxyFun.MintClosed.selector);
        nft.freeMint();
        vm.prank(paidWallet);
        vm.expectRevert(SpoxyFun.MintClosed.selector);
        nft.mint{value: 0.001 ether}();
    }

    function testWithdrawCollectedPaidFees() public {
        _open();
        vm.prank(paidWallet);
        nft.mint{value: 0.001 ether}();
        uint256 beforeBalance = owner.balance;
        vm.prank(owner);
        nft.withdraw();
        assertEq(owner.balance, beforeBalance + 0.001 ether);
        assertEq(address(nft).balance, 0);
    }

    function testTokenURI() public {
        _open();
        vm.prank(paidWallet);
        nft.mint{value: 0.001 ether}();
        uint256 id;
        for (uint256 i = 1; i <= 2222; ++i) {
            try nft.ownerOf(i) returns (address who) { if (who == paidWallet) { id = i; break; } } catch {}
        }
        assertGt(id, 0);
        assertEq(nft.tokenURI(id), string.concat(BASE, vm.toString(id), ".json"));
    }
}
