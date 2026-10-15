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
import {Waterfall} from "./Waterfall.sol";

/// @title Stepwell
/// @notice First-loss cover for one ERC-4626 vault. Everything deposited here goes into that
///         vault. Depositors hold covered shares (this token). Underwriters hold cover shares.
///         A loss in the vault comes out of the cover layer until it is gone; only then does it
///         reach covered deposits. Depositors pay for that with a slice of their interest,
///         larger when cover is thin.
/// @dev Deposits go through a request-then-settle queue modelled on ERC-7540: a requested
///      deposit spends a warm-up period earning and losing like a plain vault deposit before it
///      becomes covered, so cover cannot be bought just before a loss that is already visible.
///      Exits (withdraw, redeem) are synchronous ERC-4626. No owner, no admin, no upgrades.
contract Stepwell is ERC20, IERC4626, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;

    struct Params {
        uint16 floorBps; // new deposit requests are refused if cover would fall below this ratio
        uint16 coverLowBps; // at or below this cover ratio the premium is premiumHighBps
        uint16 coverHighBps; // at or above this cover ratio the premium is premiumLowBps
        uint16 premiumHighBps; // share of depositors' interest passed up when cover is thin
        uint16 premiumLowBps; // share passed up when cover is thick
        uint32 noticeSeconds; // how long an underwriter waits before leaving
        uint32 claimWindowSeconds; // how long a matured notice stays valid
        uint32 warmupSeconds; // how long a deposit waits before it is covered
    }

    struct Notice {
        uint128 shares;
        uint128 valueAtNotice; // the most the notice can pay out: noticed shares stop earning
        uint64 readyAt;
        uint64 epoch;
    }

    struct Request {
        uint256 shares; // settling shares
        uint64 readyAt;
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
        uint256 settlingAssets;
        uint256 coverBps;
        uint256 premiumBps;
        uint256 floorBps;
        uint256 noticeSeconds;
        uint256 warmupSeconds;
        uint256 coverUnderNotice; // cover that has given notice and may leave soon
        uint256 lossAbsorbed;
        uint256 lossPassedThrough;
        uint256 interestToCover;
        uint256 coverDeficit; // past losses cover is still owed back from future interest
    }

    uint8 public constant KIND_DEPOSIT_REQUESTED = 1;
    uint8 public constant KIND_COVERED_EXIT = 2;
    uint8 public constant KIND_COVER_DEPOSIT = 3;
    uint8 public constant KIND_NOTICE = 4;
    uint8 public constant KIND_COVER_EXIT = 5;
    uint8 public constant KIND_INTEREST = 6;
    uint8 public constant KIND_LOSS = 7;
    uint8 public constant KIND_WIPE = 8;
    uint8 public constant KIND_EXIT_IN_KIND = 9;
    uint8 public constant KIND_SETTLED = 10;
    uint8 public constant KIND_REQUEST_CANCELLED = 11;

    uint256 private constant BPS = 10_000;
    uint256 private constant HISTORY = 64;

    IERC20 private immutable _asset;
    IERC4626 public immutable underlying;
    CoverToken public immutable cover;
    uint256 private immutable _offset; // virtual shares, against share-price inflation
    uint8 private immutable _decimals;

    uint16 public immutable floorBps;
    uint16 public immutable coverLowBps;
    uint16 public immutable coverHighBps;
    uint16 public immutable premiumHighBps;
    uint16 public immutable premiumLowBps;
    uint32 public immutable noticeSeconds;
    uint32 public immutable claimWindowSeconds;
    uint32 public immutable warmupSeconds;

    uint256 public settlingAssets;
    uint256 public deepAssets;
    uint256 public coverAssets;
    uint256 public deepDeficit;
    uint256 public coverDeficit;

    uint256 public totalSettlingShares;
    mapping(address => Request) public requests;

    uint256 public lossAbsorbed;
    uint256 public lossPassedThrough;
    uint256 public interestToCover;

    mapping(address => Notice) public notices;
    uint256 public noticedShares;

    Revision[HISTORY] private _revisions;
    uint256 public revisionCount;

    event Booked(uint256 gain, uint256 loss, uint256 premium, uint256 deepAssets, uint256 coverAssets);
    event DepositRequest(address indexed controller, address indexed owner, uint256 indexed requestId, address sender, uint256 assets);
    event DepositSettled(address indexed controller, uint256 assets, uint256 shares);
    event DepositRequestCancelled(address indexed controller, uint256 assets);
    event CoverDeposit(address indexed caller, address indexed receiver, uint256 assets, uint256 shares);
    event NoticeGiven(address indexed owner, uint256 shares, uint256 readyAt, uint256 valueCap);
    event NoticeCancelled(address indexed owner);
    event CoverExit(address indexed owner, address indexed receiver, uint256 assets, uint256 shares, bool inKind);
    event CoverWiped(uint256 epoch);
    event ExitInKind(address indexed owner, address indexed receiver, uint256 assets, uint256 underlyingShares);

    error BadParams();
    error ZeroAmount();
    error NotEnoughCover(uint256 maxRequest);
    error UseRequestDeposit();
    error NotReady(uint256 readyAt);
    error NoticeExpired();
    error NoNotice();
    error NoRequest();
    error InsufficientShares();
    error NotController();
    error ExceedsLiquidity(uint256 max);

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
        _offset = 10 ** 6;
        _decimals = d + 6;
        cover = new CoverToken(string.concat(name_, " cover"), string.concat(symbol_, "-C"), d + 6);
        floorBps = p.floorBps;
        coverLowBps = p.coverLowBps;
        coverHighBps = p.coverHighBps;
        premiumHighBps = p.premiumHighBps;
        premiumLowBps = p.premiumLowBps;
        noticeSeconds = p.noticeSeconds;
        claimWindowSeconds = p.claimWindowSeconds;
        warmupSeconds = p.warmupSeconds;
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

    function _state() internal view returns (Waterfall.State memory) {
        return Waterfall.State(settlingAssets, deepAssets, coverAssets, deepDeficit, coverDeficit);
    }

    function _holders() internal view returns (Waterfall.Holders memory) {
        return Waterfall.Holders(totalSettlingShares > 0, totalSupply() > 0, cover.totalSupply() > 0);
    }

    /// @notice The buckets as they would stand after booking, without writing anything.
    function settledState() public view returns (Waterfall.State memory n) {
        (n,) = Waterfall.split(_state(), holdings(), _holders(), premiumBpsAt(deepAssets, coverAssets));
    }

    /// @notice Covered deposits and cover as they would stand after booking.
    function settled() public view returns (uint256 deep, uint256 coverAmt) {
        Waterfall.State memory n = settledState();
        return (n.deep, n.cover);
    }

    /// @notice Books interest or loss into the buckets. Anyone may call it.
    function sync() public {
        _sync();
    }

    function _sync() internal {
        uint256 h = holdings();
        uint256 oldCover = coverAssets;
        bool coverHolders = cover.totalSupply() > 0;
        (Waterfall.State memory n, Waterfall.Result memory r) =
            Waterfall.split(_state(), h, _holders(), premiumBpsAt(deepAssets, coverAssets));
        if (r.gain == 0 && r.loss == 0) return;
        settlingAssets = n.settling;
        deepAssets = n.deep;
        coverAssets = n.cover;
        deepDeficit = n.deepDeficit;
        coverDeficit = n.coverDeficit;
        if (r.gain > 0) {
            interestToCover += r.premium;
            _record(KIND_INTEREST, r.gain);
        } else {
            lossAbsorbed += r.absorbed;
            lossPassedThrough += r.passedThrough;
            _record(KIND_LOSS, r.loss);
            if (n.cover == 0 && coverHolders && oldCover > 0) {
                cover.wipe();
                coverDeficit = 0; // a fresh layer is owed nothing
                noticedShares = 0;
                emit CoverWiped(cover.epoch());
                _record(KIND_WIPE, oldCover);
            }
        }
        emit Booked(r.gain, r.loss, r.premium, deepAssets, coverAssets);
    }

    // ---------------------------------------------------------------------------------------
    // Deposits: request, warm up, settle
    // ---------------------------------------------------------------------------------------

    /// @notice The most that can be requested before cover would fall below the floor.
    function maxRequest() public view returns (uint256) {
        Waterfall.State memory n = settledState();
        uint256 room;
        if (floorBps == 0) {
            room = type(uint256).max;
        } else {
            uint256 cap = n.cover * BPS / floorBps;
            uint256 used = n.deep + n.cover + n.settling;
            room = cap > used ? cap - used : 0;
        }
        // Morpho Vault V2 reports 0 here by design ("gross underestimation"), so 0 means unknown
        uint256 u = underlying.maxDeposit(address(this));
        return u == 0 || room < u ? room : u;
    }

    /// @notice Ask to make a covered deposit. The assets earn and lose like a plain vault deposit
    ///         for `warmupSeconds`, then `settle` turns them into covered shares.
    function requestDeposit(uint256 assets, address controller, address owner)
        external
        nonReentrant
        returns (uint256 requestId)
    {
        if (assets == 0) revert ZeroAmount();
        // only the depositor can add to their own request: otherwise anyone could top it up with
        // dust and restart its warm-up forever
        if (msg.sender != owner || controller != owner) revert NotController();
        _sync();
        uint256 limit = maxRequest();
        if (assets > limit) revert NotEnoughCover(limit);
        uint256 received = _pullAndInvest(assets);
        uint256 shares = received.mulDiv(totalSettlingShares + _offset, settlingAssets + 1, Math.Rounding.Floor);
        if (shares == 0) revert ZeroAmount();
        settlingAssets += received;
        totalSettlingShares += shares;
        Request storage q = requests[controller];
        q.shares += shares;
        q.readyAt = uint64(block.timestamp + warmupSeconds); // topping up restarts the warm-up
        emit DepositRequest(controller, owner, 0, msg.sender, received);
        _record(KIND_DEPOSIT_REQUESTED, received);
        return 0;
    }

    function pendingDepositRequest(uint256, address controller) external view returns (uint256 assets) {
        Request memory q = requests[controller];
        if (q.shares == 0 || block.timestamp >= q.readyAt) return 0;
        return _settlingValue(q.shares);
    }

    function claimableDepositRequest(uint256, address controller) external view returns (uint256 assets) {
        Request memory q = requests[controller];
        if (q.shares == 0 || block.timestamp < q.readyAt) return 0;
        return _settlingValue(q.shares);
    }

    function _settlingValue(uint256 shares) internal view returns (uint256) {
        Waterfall.State memory n = settledState();
        return shares.mulDiv(n.settling + 1, totalSettlingShares + _offset, Math.Rounding.Floor);
    }

    /// @notice Turn a warmed-up request into covered shares. Anyone may call it for anyone, so a
    ///         relayer or the app can do it without the depositor coming back.
    function settle(address controller) public nonReentrant returns (uint256 shares) {
        Request memory q = requests[controller];
        if (q.shares == 0) revert NoRequest();
        if (block.timestamp < q.readyAt) revert NotReady(q.readyAt);
        _sync();
        uint256 assets = q.shares.mulDiv(settlingAssets + 1, totalSettlingShares + _offset, Math.Rounding.Floor);
        if (assets > settlingAssets) assets = settlingAssets;
        delete requests[controller];
        totalSettlingShares -= q.shares;
        settlingAssets -= assets;
        shares = assets.mulDiv(totalSupply() + _offset, deepAssets + 1, Math.Rounding.Floor);
        deepAssets += assets;
        _mint(controller, shares);
        emit Deposit(msg.sender, controller, assets, shares);
        emit DepositSettled(controller, assets, shares);
        _record(KIND_SETTLED, assets);
    }

    /// @notice Withdraw a request before it settles, at whatever it is worth now.
    function cancelDepositRequest(address receiver) external nonReentrant returns (uint256 assets) {
        Request memory q = requests[msg.sender];
        if (q.shares == 0) revert NoRequest();
        _sync();
        assets = q.shares.mulDiv(settlingAssets + 1, totalSettlingShares + _offset, Math.Rounding.Floor);
        if (assets > settlingAssets) assets = settlingAssets;
        delete requests[msg.sender];
        totalSettlingShares -= q.shares;
        settlingAssets -= assets;
        if (assets > 0) underlying.withdraw(assets, receiver, address(this));
        emit DepositRequestCancelled(msg.sender, assets);
        _record(KIND_REQUEST_CANCELLED, assets);
    }

    // ---------------------------------------------------------------------------------------
    // Covered shares: ERC-4626 (synchronous deposits are off; use requestDeposit)
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

    /// @dev Every covered deposit warms up first, so the synchronous paths report zero room.
    function maxDeposit(address) public pure returns (uint256) {
        return 0;
    }

    function maxMint(address) public pure returns (uint256) {
        return 0;
    }

    function previewDeposit(uint256 assets) public view returns (uint256) {
        return convertToShares(assets);
    }

    function previewMint(uint256 shares) public view returns (uint256) {
        return shares.mulDiv(totalAssets() + 1, totalSupply() + _offset, Math.Rounding.Ceil);
    }

    function deposit(uint256, address) public pure returns (uint256) {
        revert UseRequestDeposit();
    }

    function mint(uint256, address) public pure returns (uint256) {
        revert UseRequestDeposit();
    }

    /// @dev What the vault says can leave right now. Morpho Vault V2 always reports 0 here by
    ///      design, so 0 is read as "unknown" and the vault's own withdraw decides.
    function _liquidity() internal view returns (uint256) {
        uint256 l = underlying.maxWithdraw(address(this));
        return l == 0 ? type(uint256).max : l;
    }

    function maxWithdraw(address owner) public view returns (uint256) {
        uint256 a = convertToAssets(balanceOf(owner));
        uint256 l = _liquidity();
        return a < l ? a : l;
    }

    function maxRedeem(address owner) public view returns (uint256) {
        uint256 b = balanceOf(owner);
        uint256 l = _liquidity();
        if (convertToAssets(b) <= l) return b;
        return convertToShares(l);
    }

    function previewWithdraw(uint256 assets) public view returns (uint256) {
        return assets.mulDiv(totalSupply() + _offset, totalAssets() + 1, Math.Rounding.Ceil);
    }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        return convertToAssets(shares);
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
        uint256 l = _liquidity();
        if (assets > l) revert ExceedsLiquidity(l);
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
        underlyingShares = _sharesFor(assets);
        _burn(owner, shares);
        deepAssets -= assets;
        IERC20(address(underlying)).safeTransfer(receiver, underlyingShares);
        _resyncAfterInKind();
        emit ExitInKind(owner, receiver, assets, underlyingShares);
        _record(KIND_EXIT_IN_KIND, assets);
    }

    function _sharesFor(uint256 assets) internal view returns (uint256) {
        uint256 h = holdings();
        return h == 0 ? 0 : underlying.balanceOf(address(this)).mulDiv(assets, h, Math.Rounding.Floor);
    }

    /// @dev Rounding in the vault's share maths can leave the books a unit above holdings after
    ///      shares leave in kind. The cover layer absorbs that unit, as it would any other loss.
    function _resyncAfterInKind() internal {
        uint256 h = holdings();
        uint256 booked = settlingAssets + deepAssets + coverAssets;
        if (h < booked) {
            uint256 gap = booked - h;
            if (gap <= coverAssets) {
                coverAssets -= gap;
            } else {
                deepAssets -= gap - coverAssets;
                coverAssets = 0;
            }
        }
    }

    // ---------------------------------------------------------------------------------------
    // The cover layer
    // ---------------------------------------------------------------------------------------

    function coverValueOf(uint256 shares) public view returns (uint256) {
        (, uint256 c) = settled();
        return shares.mulDiv(c + 1, cover.totalSupply() + _offset, Math.Rounding.Floor);
    }

    function coverBalanceAssets(address account) external view returns (uint256) {
        return coverValueOf(cover.balanceOf(account));
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

    /// @notice Start the notice period on some cover shares. From now on they keep taking losses
    ///         but stop earning: the payout is capped at what they are worth today.
    function giveNotice(uint256 shares) external {
        if (shares == 0 || shares > type(uint128).max) revert ZeroAmount();
        _sync(); // book first: a loss may have wiped the layer and voided these shares
        if (cover.balanceOf(msg.sender) < shares) revert InsufficientShares();
        Notice memory old = notices[msg.sender];
        if (old.shares > 0 && old.epoch == cover.epoch()) {
            noticedShares -= old.shares;
            _forfeitNoticeGain(old);
        }
        if (shares > cover.balanceOf(msg.sender)) shares = cover.balanceOf(msg.sender); // after any forfeit
        if (shares == 0) revert ZeroAmount();
        uint256 cap = shares.mulDiv(coverAssets + 1, cover.totalSupply() + _offset, Math.Rounding.Floor);
        uint256 readyAt = block.timestamp + noticeSeconds;
        notices[msg.sender] = Notice(uint128(shares), uint128(cap), uint64(readyAt), uint64(cover.epoch()));
        noticedShares += shares;
        emit NoticeGiven(msg.sender, shares, readyAt, cap);
        _record(KIND_NOTICE, cap);
    }

    function cancelNotice() external {
        Notice memory n = notices[msg.sender];
        _sync();
        if (n.shares > 0 && n.epoch == cover.epoch()) {
            noticedShares -= n.shares;
            _forfeitNoticeGain(n);
        }
        delete notices[msg.sender];
        emit NoticeCancelled(msg.sender);
    }

    /// Noticed shares stop earning however the notice ends. Cancelling or renewing a notice gives
    /// up whatever the noticed shares gained since notice day: that many cover shares are burned
    /// and their value stays with the rest of the cover layer.
    function _forfeitNoticeGain(Notice memory n) internal {
        uint256 ts = cover.totalSupply() + _offset;
        uint256 a = coverAssets + 1;
        uint256 value = uint256(n.shares).mulDiv(a, ts, Math.Rounding.Floor);
        uint256 cap = n.valueAtNotice;
        if (value <= cap || cap >= a) return; // nothing gained, or nobody else to give it to
        // keep k of the noticed shares so that, after burning the rest, those k are worth `cap`:
        // k * a / (ts - (shares - k)) = cap  =>  k = cap * (ts - shares) / (a - cap)
        uint256 keep = cap.mulDiv(ts - n.shares, a - cap, Math.Rounding.Ceil);
        if (keep >= n.shares) return;
        uint256 burn = n.shares - keep;
        uint256 bal = cover.balanceOf(msg.sender);
        if (burn > bal) burn = bal;
        if (burn > 0) cover.burn(msg.sender, burn);
    }

    /// @notice Leave the cover layer once notice has run, in USDC.
    function claimCover(address receiver) external nonReentrant returns (uint256 assets) {
        uint256 shares;
        (assets, shares) = _claimCoverAccounting();
        uint256 l = _liquidity();
        if (assets > l) revert ExceedsLiquidity(l);
        if (assets > 0) underlying.withdraw(assets, receiver, address(this));
        emit CoverExit(msg.sender, receiver, assets, shares, false);
        _record(KIND_COVER_EXIT, assets);
    }

    /// @notice Leave the cover layer once notice has run, with vault shares instead of USDC.
    function claimCoverInKind(address receiver) external nonReentrant returns (uint256 underlyingShares) {
        (uint256 assets, uint256 shares) = _claimCoverAccounting();
        underlyingShares = _sharesFor(assets);
        IERC20(address(underlying)).safeTransfer(receiver, underlyingShares);
        _resyncAfterInKind();
        emit CoverExit(msg.sender, receiver, assets, shares, true);
        _record(KIND_COVER_EXIT, assets);
    }

    function _claimCoverAccounting() internal returns (uint256 assets, uint256 shares) {
        Notice memory n = notices[msg.sender];
        if (n.shares == 0) revert NoNotice();
        _sync();
        if (n.epoch != cover.epoch()) revert NoNotice();
        if (block.timestamp < n.readyAt) revert NotReady(n.readyAt);
        if (block.timestamp > uint256(n.readyAt) + claimWindowSeconds) revert NoticeExpired();
        shares = n.shares;
        if (cover.balanceOf(msg.sender) < shares) revert InsufficientShares();
        assets = shares.mulDiv(coverAssets + 1, cover.totalSupply() + _offset, Math.Rounding.Floor);
        if (assets > n.valueAtNotice) assets = n.valueAtNotice; // noticed shares do not earn
        if (assets > coverAssets) assets = coverAssets;
        delete notices[msg.sender];
        noticedShares -= shares;
        cover.burn(msg.sender, shares);
        coverAssets -= assets;
    }

    // ---------------------------------------------------------------------------------------
    // Coverage metadata and history
    // ---------------------------------------------------------------------------------------

    /// @notice One call that tells any app how well a vault is covered.
    function coverage() external view returns (Coverage memory c) {
        Waterfall.State memory n = settledState();
        uint256 total = n.deep + n.cover;
        c.underlying = address(underlying);
        c.coveredAssets = n.deep;
        c.coverAssets = n.cover;
        c.settlingAssets = n.settling;
        c.coverBps = total == 0 ? 0 : n.cover * BPS / total;
        c.premiumBps = premiumBpsAt(n.deep, n.cover);
        c.floorBps = floorBps;
        c.noticeSeconds = noticeSeconds;
        c.warmupSeconds = warmupSeconds;
        c.coverUnderNotice = noticedShares.mulDiv(n.cover + 1, cover.totalSupply() + _offset, Math.Rounding.Floor);
        c.lossAbsorbed = lossAbsorbed;
        c.lossPassedThrough = lossPassedThrough;
        c.interestToCover = interestToCover;
        c.coverDeficit = n.coverDeficit;
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
            uint128(Math.min(amount, type(uint128).max)),
            uint128(Math.min(deepAssets, type(uint128).max)),
            uint128(Math.min(coverAssets, type(uint128).max))
        );
        revisionCount += 1;
    }

    // ---------------------------------------------------------------------------------------

    /// @dev Credits what the new vault shares are worth, so rounding inside the vault is borne by
    ///      the person depositing. Measured from the shares minted, not from holdings before and
    ///      after: Morpho Vault V2 caches its totals within a transaction.
    function _pullAndInvest(uint256 assets) internal returns (uint256 received) {
        _asset.safeTransferFrom(msg.sender, address(this), assets);
        _asset.forceApprove(address(underlying), assets);
        uint256 minted = underlying.deposit(assets, address(this));
        received = underlying.previewRedeem(minted);
        if (received > assets) received = assets;
    }

    function decimals() public view override(ERC20, IERC20Metadata) returns (uint8) {
        return _decimals;
    }
}
