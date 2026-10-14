// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {CoverToken} from "./CoverToken.sol";

/// @title Stepwell
/// @notice First-loss cover for one ERC-4626 vault. Everything deposited here goes into that
///         vault. Depositors hold covered shares (this token, an ERC-4626 vault itself).
///         Underwriters hold cover shares. A loss in the vault comes out of the cover layer
///         until it is gone; only then does it reach depositors. In return depositors pass a
///         slice of their interest to the cover layer, larger when cover is thin.
/// @dev No owner, no admin, no upgrade path. All parameters are fixed at construction.
contract Stepwell is ERC20, IERC4626, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;

    struct Params {
        uint16 floorBps; // new covered deposits are refused below this cover ratio
        uint16 coverLowBps; // at or below this cover ratio the premium is premiumHighBps
        uint16 coverHighBps; // at or above this cover ratio the premium is premiumLowBps
        uint16 premiumHighBps; // share of depositors' interest passed up when cover is thin
        uint16 premiumLowBps; // share passed up when cover is thick
        uint32 noticeSeconds; // how long an underwriter waits before leaving
        uint32 claimWindowSeconds; // how long a matured notice stays valid
    }

    struct Notice {
        uint128 shares;
        uint64 readyAt;
        uint64 epoch;
    }

    struct Revision {
        uint64 time;
        uint64 blockNumber;
        uint8 kind;
        uint128 amount;
        uint128 deep;
        uint128 cover;
    }

    struct Coverage {
        address underlying;
        uint256 coveredAssets;
        uint256 coverAssets;
        uint256 coverBps;
        uint256 premiumBps;
        uint256 floorBps;
        uint256 noticeSeconds;
        uint256 lossAbsorbed;
        uint256 lossPassedThrough;
        uint256 interestToCover;
    }

    uint8 public constant KIND_COVERED_DEPOSIT = 1;
    uint8 public constant KIND_COVERED_EXIT = 2;
    uint8 public constant KIND_COVER_DEPOSIT = 3;
    uint8 public constant KIND_NOTICE = 4;
    uint8 public constant KIND_COVER_EXIT = 5;
    uint8 public constant KIND_INTEREST = 6;
    uint8 public constant KIND_LOSS = 7;
    uint8 public constant KIND_WIPE = 8;
    uint8 public constant KIND_EXIT_IN_KIND = 9;

    uint256 private constant BPS = 10_000;
    uint256 private constant HISTORY = 64;

    IERC20 private immutable _asset;
    IERC4626 public immutable underlying;
    CoverToken public immutable cover;
    uint256 private immutable _offset; // virtual shares, against share-price inflation

    uint16 public immutable floorBps;
    uint16 public immutable coverLowBps;
    uint16 public immutable coverHighBps;
    uint16 public immutable premiumHighBps;
    uint16 public immutable premiumLowBps;
    uint32 public immutable noticeSeconds;
    uint32 public immutable claimWindowSeconds;

    /// @notice What depositors are owed, in assets, as of the last booking.
    uint256 public deepAssets;
    /// @notice What the cover layer is worth, in assets, as of the last booking.
    uint256 public coverAssets;

    uint256 public lossAbsorbed;
    uint256 public lossPassedThrough;
    uint256 public interestToCover;

    mapping(address => Notice) public notices;

    Revision[HISTORY] private _revisions;
    uint256 public revisionCount;

    event Booked(uint256 gain, uint256 loss, uint256 premium, uint256 deepAssets, uint256 coverAssets);
    event CoverDeposit(address indexed caller, address indexed receiver, uint256 assets, uint256 shares);
    event NoticeGiven(address indexed owner, uint256 shares, uint256 readyAt);
    event NoticeCancelled(address indexed owner);
    event CoverExit(address indexed owner, address indexed receiver, uint256 assets, uint256 shares);
    event CoverWiped(uint256 epoch);
    event ExitInKind(address indexed owner, address indexed receiver, uint256 assets, uint256 underlyingShares);

    error BadParams();
    error ZeroAmount();
    error NotEnoughCover(uint256 maxDeposit);
    error NoticeNotReady(uint256 readyAt);
    error NoticeExpired();
    error NoNotice();
    error InsufficientShares();

    constructor(IERC4626 underlying_, string memory name_, string memory symbol_, Params memory p)
        ERC20(name_, symbol_)
    {
        if (
            p.floorBps > BPS || p.coverLowBps >= p.coverHighBps || p.coverHighBps > BPS
                || p.premiumHighBps > BPS || p.premiumLowBps > p.premiumHighBps || p.claimWindowSeconds == 0
        ) revert BadParams();
        underlying = underlying_;
        _asset = IERC20(underlying_.asset());
        uint8 d = IERC20Metadata(address(_asset)).decimals();
        _offset = 10 ** d;
        cover = new CoverToken(string.concat(name_, " cover"), string.concat(symbol_, "-C"), decimals());
        floorBps = p.floorBps;
        coverLowBps = p.coverLowBps;
        coverHighBps = p.coverHighBps;
        premiumHighBps = p.premiumHighBps;
        premiumLowBps = p.premiumLowBps;
        noticeSeconds = p.noticeSeconds;
        claimWindowSeconds = p.claimWindowSeconds;
    }

    // ---------------------------------------------------------------------------------------
    // The waterfall
    // ---------------------------------------------------------------------------------------

    /// @notice What the vault shares held here would redeem for right now.
    function holdings() public view returns (uint256) {
        return underlying.previewRedeem(underlying.balanceOf(address(this)));
    }

    /// @notice Share of depositors' interest passed to the cover layer at a given split.
    function premiumBpsAt(uint256 deep, uint256 coverAmt) public view returns (uint256) {
        uint256 total = deep + coverAmt;
        if (total == 0) return premiumHighBps;
        uint256 ratio = coverAmt * BPS / total;
        if (ratio <= coverLowBps) return premiumHighBps;
        if (ratio >= coverHighBps) return premiumLowBps;
        return premiumHighBps
            - (premiumHighBps - premiumLowBps) * (ratio - coverLowBps) / (coverHighBps - coverLowBps);
    }

    /// @dev The split of `h` between the two layers, given the last booked split.
    function _split(uint256 deep, uint256 coverAmt, uint256 h, bool coverHolders, bool deepHolders)
        internal
        view
        returns (uint256 newDeep, uint256 newCover, uint256 gain, uint256 loss, uint256 premium)
    {
        uint256 booked = deep + coverAmt;
        newDeep = deep;
        newCover = coverAmt;
        if (h > booked) {
            gain = h - booked;
            if (!deepHolders && !coverHolders) return (deep, coverAmt, 0, 0, 0);
            if (!deepHolders || booked == 0) {
                newCover += gain;
            } else if (!coverHolders) {
                newDeep += gain;
            } else {
                uint256 deepGross = gain.mulDiv(deep, booked);
                premium = deepGross.mulDiv(premiumBpsAt(deep, coverAmt), BPS);
                newDeep += deepGross - premium;
                newCover += gain - (deepGross - premium);
            }
        } else if (h < booked) {
            loss = booked - h;
            if (loss <= coverAmt) {
                newCover -= loss;
            } else {
                newDeep -= loss - coverAmt;
                newCover = 0;
            }
        }
    }

    /// @notice Books interest or loss into the two layers. Anyone may call it.
    function sync() public {
        _sync();
    }

    function _sync() internal {
        uint256 h = holdings();
        uint256 oldCover = coverAssets;
        bool coverHolders = cover.totalSupply() > 0;
        (uint256 d, uint256 c, uint256 gain, uint256 loss, uint256 premium) =
            _split(deepAssets, coverAssets, h, coverHolders, totalSupply() > 0);
        if (gain == 0 && loss == 0) return;
        if (gain > 0 && (totalSupply() > 0 || coverHolders)) {
            interestToCover += premium;
            deepAssets = d;
            coverAssets = c;
            _record(KIND_INTEREST, gain);
        } else if (loss > 0) {
            uint256 absorbed = loss < oldCover ? loss : oldCover;
            lossAbsorbed += absorbed;
            lossPassedThrough += loss - absorbed;
            deepAssets = d;
            coverAssets = c;
            _record(KIND_LOSS, loss);
            if (c == 0 && coverHolders) {
                cover.wipe();
                emit CoverWiped(cover.epoch());
                _record(KIND_WIPE, oldCover);
            }
        }
        emit Booked(gain, loss, premium, deepAssets, coverAssets);
    }

    /// @notice The two layers as they would stand after booking, without writing anything.
    function settled() public view returns (uint256 deep, uint256 coverAmt) {
        (deep, coverAmt,,,) =
            _split(deepAssets, coverAssets, holdings(), cover.totalSupply() > 0, totalSupply() > 0);
    }

    // ---------------------------------------------------------------------------------------
    // Covered deposits: ERC-4626
    // ---------------------------------------------------------------------------------------

    function asset() public view returns (address) {
        return address(_asset);
    }

    function totalAssets() public view returns (uint256 deep) {
        (deep,) = settled();
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        return assets.mulDiv(totalSupply() + _offset, totalAssets() + 1, Math.Rounding.Floor);
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        return shares.mulDiv(totalAssets() + 1, totalSupply() + _offset, Math.Rounding.Floor);
    }

    /// @notice The most that can be deposited before cover would fall below the floor.
    function maxDeposit(address) public view returns (uint256) {
        (uint256 deep, uint256 c) = settled();
        if (floorBps == 0) return type(uint256).max;
        uint256 cap = c * BPS / floorBps; // largest total that keeps c / total >= floor
        return cap > deep + c ? cap - deep - c : 0;
    }

    function maxMint(address receiver) public view returns (uint256) {
        uint256 m = maxDeposit(receiver);
        return m == type(uint256).max ? m : convertToShares(m);
    }

    function maxWithdraw(address owner) public view returns (uint256) {
        return convertToAssets(balanceOf(owner));
    }

    function maxRedeem(address owner) public view returns (uint256) {
        return balanceOf(owner);
    }

    function previewDeposit(uint256 assets) public view returns (uint256) {
        return convertToShares(assets);
    }

    function previewMint(uint256 shares) public view returns (uint256) {
        return shares.mulDiv(totalAssets() + 1, totalSupply() + _offset, Math.Rounding.Ceil);
    }

    function previewWithdraw(uint256 assets) public view returns (uint256) {
        return assets.mulDiv(totalSupply() + _offset, totalAssets() + 1, Math.Rounding.Ceil);
    }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        return convertToAssets(shares);
    }

    function deposit(uint256 assets, address receiver) public nonReentrant returns (uint256 shares) {
        shares = _depositCovered(assets, receiver);
    }

    function mint(uint256 shares, address receiver) public nonReentrant returns (uint256 assets) {
        _sync();
        assets = shares.mulDiv(deepAssets + 1, totalSupply() + _offset, Math.Rounding.Ceil);
        _depositCovered(assets, receiver);
    }

    function _depositCovered(uint256 assets, address receiver) internal returns (uint256 shares) {
        if (assets == 0) revert ZeroAmount();
        _sync();
        uint256 limit = maxDeposit(receiver);
        if (assets > limit) revert NotEnoughCover(limit);
        uint256 received = _pullAndInvest(assets);
        // Shares are priced on what actually reached the vault, so rounding inside the vault is
        // borne by this depositor and never by the people already here.
        shares = received.mulDiv(totalSupply() + _offset, deepAssets + 1, Math.Rounding.Floor);
        if (shares == 0) revert ZeroAmount();
        deepAssets += received;
        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
        _record(KIND_COVERED_DEPOSIT, received);
    }

    function withdraw(uint256 assets, address receiver, address owner)
        public
        nonReentrant
        returns (uint256 shares)
    {
        _sync();
        shares = assets.mulDiv(totalSupply() + _offset, deepAssets + 1, Math.Rounding.Ceil);
        _exitCovered(assets, shares, receiver, owner);
    }

    function redeem(uint256 shares, address receiver, address owner)
        public
        nonReentrant
        returns (uint256 assets)
    {
        _sync();
        assets = shares.mulDiv(deepAssets + 1, totalSupply() + _offset, Math.Rounding.Floor);
        _exitCovered(assets, shares, receiver, owner);
    }

    function _exitCovered(uint256 assets, uint256 shares, address receiver, address owner) internal {
        if (shares == 0 || assets == 0) revert ZeroAmount();
        if (msg.sender != owner) _spendAllowance(owner, msg.sender, shares);
        if (assets > deepAssets) assets = deepAssets;
        _burn(owner, shares);
        deepAssets -= assets;
        underlying.withdraw(assets, receiver, address(this));
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        _record(KIND_COVERED_EXIT, assets);
    }

    /// @notice Leave with vault shares instead of USDC, for when the vault is short of cash.
    function redeemInKind(uint256 shares, address receiver, address owner)
        external
        nonReentrant
        returns (uint256 underlyingShares)
    {
        _sync();
        if (shares == 0) revert ZeroAmount();
        if (msg.sender != owner) _spendAllowance(owner, msg.sender, shares);
        uint256 assets = shares.mulDiv(deepAssets + 1, totalSupply() + _offset, Math.Rounding.Floor);
        if (assets > deepAssets) assets = deepAssets;
        uint256 held = underlying.balanceOf(address(this));
        uint256 h = holdings();
        underlyingShares = h == 0 ? 0 : held.mulDiv(assets, h, Math.Rounding.Floor);
        _burn(owner, shares);
        deepAssets -= assets;
        IERC20(address(underlying)).safeTransfer(receiver, underlyingShares);
        _resyncAfterInKind();
        emit ExitInKind(owner, receiver, assets, underlyingShares);
        _record(KIND_EXIT_IN_KIND, assets);
    }

    /// @dev Rounding in the vault's share maths can leave the books a unit above holdings after
    ///      shares leave in kind. The cover layer absorbs that unit, as it would any other loss.
    function _resyncAfterInKind() internal {
        uint256 h = holdings();
        uint256 booked = deepAssets + coverAssets;
        if (h < booked) {
            uint256 gap = booked - h;
            if (gap <= coverAssets) coverAssets -= gap;
            else {
                deepAssets -= gap - coverAssets;
                coverAssets = 0;
            }
        }
    }

    // ---------------------------------------------------------------------------------------
    // The cover layer
    // ---------------------------------------------------------------------------------------

    function coverPrice() public view returns (uint256 assetsPerShare) {
        (, uint256 c) = settled();
        return _offset.mulDiv(c + 1, cover.totalSupply() + _offset, Math.Rounding.Floor);
    }

    function coverBalanceAssets(address account) external view returns (uint256) {
        (, uint256 c) = settled();
        return cover.balanceOf(account).mulDiv(c + 1, cover.totalSupply() + _offset, Math.Rounding.Floor);
    }

    function depositCover(uint256 assets, address receiver) external nonReentrant returns (uint256 shares) {
        if (assets == 0) revert ZeroAmount();
        _sync();
        uint256 received = _pullAndInvest(assets);
        shares = received.mulDiv(cover.totalSupply() + _offset, coverAssets + 1, Math.Rounding.Floor);
        if (shares == 0) revert ZeroAmount();
        coverAssets += received;
        cover.mint(receiver, shares);
        emit CoverDeposit(msg.sender, receiver, received, shares);
        _record(KIND_COVER_DEPOSIT, received);
    }

    /// @notice Start the notice period on some cover shares. They keep bearing losses until claimed.
    function giveNotice(uint256 shares) external {
        if (shares == 0) revert ZeroAmount();
        if (cover.balanceOf(msg.sender) < shares) revert InsufficientShares();
        uint256 readyAt = block.timestamp + noticeSeconds;
        notices[msg.sender] = Notice(uint128(shares), uint64(readyAt), uint64(cover.epoch()));
        emit NoticeGiven(msg.sender, shares, readyAt);
        _record(KIND_NOTICE, shares);
    }

    function cancelNotice() external {
        delete notices[msg.sender];
        emit NoticeCancelled(msg.sender);
    }

    /// @notice Leave the cover layer once notice has run.
    function claimCover(address receiver) external nonReentrant returns (uint256 assets) {
        Notice memory n = notices[msg.sender];
        if (n.shares == 0) revert NoNotice();
        _sync();
        if (n.epoch != cover.epoch()) {
            delete notices[msg.sender];
            revert NoNotice();
        }
        if (block.timestamp < n.readyAt) revert NoticeNotReady(n.readyAt);
        if (block.timestamp > uint256(n.readyAt) + claimWindowSeconds) revert NoticeExpired();
        uint256 shares = n.shares;
        if (cover.balanceOf(msg.sender) < shares) revert InsufficientShares();
        assets = shares.mulDiv(coverAssets + 1, cover.totalSupply() + _offset, Math.Rounding.Floor);
        if (assets > coverAssets) assets = coverAssets;
        delete notices[msg.sender];
        cover.burn(msg.sender, shares);
        coverAssets -= assets;
        if (assets > 0) underlying.withdraw(assets, receiver, address(this));
        emit CoverExit(msg.sender, receiver, assets, shares);
        _record(KIND_COVER_EXIT, assets);
    }

    // ---------------------------------------------------------------------------------------
    // Coverage metadata and history
    // ---------------------------------------------------------------------------------------

    /// @notice One call that tells any app how well a vault is covered.
    function coverage() external view returns (Coverage memory c) {
        (uint256 deep, uint256 cov) = settled();
        uint256 total = deep + cov;
        c.underlying = address(underlying);
        c.coveredAssets = deep;
        c.coverAssets = cov;
        c.coverBps = total == 0 ? 0 : cov * BPS / total;
        c.premiumBps = premiumBpsAt(deep, cov);
        c.floorBps = floorBps;
        c.noticeSeconds = noticeSeconds;
        c.lossAbsorbed = lossAbsorbed;
        c.lossPassedThrough = lossPassedThrough;
        c.interestToCover = interestToCover;
    }

    /// @notice The most recent entries, newest first. Kept in storage so the history never
    ///         depends on an RPC node still serving old receipts.
    function revisions(uint256 count) external view returns (Revision[] memory out) {
        uint256 n = revisionCount < HISTORY ? revisionCount : HISTORY;
        if (count > n) count = n;
        out = new Revision[](count);
        for (uint256 i = 0; i < count; i++) {
            out[i] = _revisions[(revisionCount - 1 - i) % HISTORY];
        }
    }

    function _record(uint8 kind, uint256 amount) internal {
        _revisions[revisionCount % HISTORY] = Revision(
            uint64(block.timestamp),
            uint64(block.number),
            kind,
            uint128(amount),
            uint128(deepAssets),
            uint128(coverAssets)
        );
        revisionCount += 1;
    }

    // ---------------------------------------------------------------------------------------

    function _pullAndInvest(uint256 assets) internal returns (uint256 received) {
        _asset.safeTransferFrom(msg.sender, address(this), assets);
        uint256 before = holdings();
        _asset.forceApprove(address(underlying), assets);
        underlying.deposit(assets, address(this));
        received = holdings() - before;
    }

    function decimals() public view override(ERC20, IERC20Metadata) returns (uint8) {
        return IERC20Metadata(address(_asset)).decimals();
    }
}
