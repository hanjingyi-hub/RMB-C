// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title RMBC
/// @notice A USDC-style centrally issued ERC-20 stablecoin prototype.
contract RMBC {
    string public constant name = "RMB Coin";
    string public constant symbol = "RMBC";
    string public constant version = "1";
    uint8 public constant decimals = 6;

    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 private constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    uint256 private constant SECP256K1_HALF_ORDER =
        0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0;

    uint256 public totalSupply;
    address public owner;
    bool public paused;

    mapping(address account => uint256 balance) public balanceOf;
    mapping(address account => mapping(address spender => uint256 allowanceAmount)) public allowance;
    mapping(address account => bool allowed) public isMinter;
    mapping(address minter => uint256 amount) public minterAllowance;
    mapping(address account => bool denied) public denied;
    mapping(address account => uint256 nonce) public nonces;

    event Approval(address indexed tokenOwner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event MinterConfigured(address indexed minter, uint256 allowanceAmount);
    event MinterRemoved(address indexed minter);
    event Paused(address indexed account);
    event Unpaused(address indexed account);
    event AccountDenied(address indexed account);
    event AccountAllowed(address indexed account);
    event DeniedFundsDestroyed(address indexed account, uint256 amount);

    error AllowanceExceeded(uint256 available, uint256 required);
    error AmountExceedsBalance(uint256 available, uint256 required);
    error DeniedAddress(address account);
    error AddressNotDenied(address account);
    error ExpiredPermit(uint256 deadline);
    error InvalidAddress();
    error InvalidSignature();
    error MinterAllowanceExceeded(uint256 available, uint256 required);
    error NotMinter(address account);
    error NotOwner(address account);
    error PausedToken();

    constructor(address initialOwner) {
        if (initialOwner == address(0)) {
            revert InvalidAddress();
        }

        owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert NotOwner(msg.sender);
        }
        _;
    }

    modifier whenNotPaused() {
        if (paused) {
            revert PausedToken();
        }
        _;
    }

    modifier notDenied(address account) {
        if (denied[account]) {
            revert DeniedAddress(account);
        }
        _;
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return _domainSeparator();
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) {
            revert InvalidAddress();
        }

        address previousOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }

    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }

    function configureMinter(address minter, uint256 allowanceAmount)
        external
        onlyOwner
        notDenied(minter)
    {
        if (minter == address(0)) {
            revert InvalidAddress();
        }

        isMinter[minter] = true;
        minterAllowance[minter] = allowanceAmount;
        emit MinterConfigured(minter, allowanceAmount);
    }

    function removeMinter(address minter) external onlyOwner {
        isMinter[minter] = false;
        minterAllowance[minter] = 0;
        emit MinterRemoved(minter);
    }

    function deny(address account) external onlyOwner {
        if (account == address(0)) {
            revert InvalidAddress();
        }

        denied[account] = true;
        emit AccountDenied(account);
    }

    function allow(address account) external onlyOwner {
        denied[account] = false;
        emit AccountAllowed(account);
    }

    function destroyDeniedFunds(address account) external onlyOwner {
        if (!denied[account]) {
            revert AddressNotDenied(account);
        }

        uint256 amount = balanceOf[account];
        balanceOf[account] = 0;
        totalSupply -= amount;

        emit DeniedFundsDestroyed(account, amount);
        emit Transfer(account, address(0), amount);
    }

    function mint(address to, uint256 amount)
        external
        whenNotPaused
        notDenied(msg.sender)
        notDenied(to)
        returns (bool)
    {
        if (!isMinter[msg.sender]) {
            revert NotMinter(msg.sender);
        }
        if (to == address(0)) {
            revert InvalidAddress();
        }

        uint256 available = minterAllowance[msg.sender];
        if (amount > available) {
            revert MinterAllowanceExceeded(available, amount);
        }

        minterAllowance[msg.sender] = available - amount;
        totalSupply += amount;
        balanceOf[to] += amount;

        emit Transfer(address(0), to, amount);
        return true;
    }

    function burn(uint256 amount) external whenNotPaused notDenied(msg.sender) returns (bool) {
        if (!isMinter[msg.sender]) {
            revert NotMinter(msg.sender);
        }

        _burn(msg.sender, amount);
        return true;
    }

    function transfer(address to, uint256 amount)
        external
        whenNotPaused
        notDenied(msg.sender)
        notDenied(to)
        returns (bool)
    {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount)
        external
        whenNotPaused
        notDenied(msg.sender)
        notDenied(spender)
        returns (bool)
    {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue)
        external
        whenNotPaused
        notDenied(msg.sender)
        notDenied(spender)
        returns (bool)
    {
        _approve(msg.sender, spender, allowance[msg.sender][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        external
        whenNotPaused
        notDenied(msg.sender)
        notDenied(spender)
        returns (bool)
    {
        uint256 currentAllowance = allowance[msg.sender][spender];
        if (subtractedValue > currentAllowance) {
            revert AllowanceExceeded(currentAllowance, subtractedValue);
        }

        _approve(msg.sender, spender, currentAllowance - subtractedValue);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount)
        external
        whenNotPaused
        notDenied(msg.sender)
        notDenied(from)
        notDenied(to)
        returns (bool)
    {
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function permit(
        address tokenOwner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
        whenNotPaused
        notDenied(tokenOwner)
        notDenied(spender)
    {
        if (block.timestamp > deadline) {
            revert ExpiredPermit(deadline);
        }
        if (tokenOwner == address(0) || spender == address(0)) {
            revert InvalidAddress();
        }
        if (v != 27 && v != 28) {
            revert InvalidSignature();
        }
        if (uint256(s) > SECP256K1_HALF_ORDER) {
            revert InvalidSignature();
        }

        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                tokenOwner,
                spender,
                value,
                nonces[tokenOwner]++,
                deadline
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        address signer = ecrecover(digest, v, r, s);
        if (signer != tokenOwner) {
            revert InvalidSignature();
        }

        _approve(tokenOwner, spender, value);
    }

    function _transfer(address from, address to, uint256 amount) private {
        if (to == address(0)) {
            revert InvalidAddress();
        }

        uint256 fromBalance = balanceOf[from];
        if (amount > fromBalance) {
            revert AmountExceedsBalance(fromBalance, amount);
        }

        balanceOf[from] = fromBalance - amount;
        balanceOf[to] += amount;

        emit Transfer(from, to, amount);
    }

    function _burn(address from, uint256 amount) private {
        uint256 fromBalance = balanceOf[from];
        if (amount > fromBalance) {
            revert AmountExceedsBalance(fromBalance, amount);
        }

        balanceOf[from] = fromBalance - amount;
        totalSupply -= amount;

        emit Transfer(from, address(0), amount);
    }

    function _approve(address tokenOwner, address spender, uint256 amount) private {
        if (tokenOwner == address(0) || spender == address(0)) {
            revert InvalidAddress();
        }

        allowance[tokenOwner][spender] = amount;
        emit Approval(tokenOwner, spender, amount);
    }

    function _spendAllowance(address tokenOwner, address spender, uint256 amount) private {
        uint256 currentAllowance = allowance[tokenOwner][spender];
        if (currentAllowance != type(uint256).max) {
            if (amount > currentAllowance) {
                revert AllowanceExceeded(currentAllowance, amount);
            }

            unchecked {
                allowance[tokenOwner][spender] = currentAllowance - amount;
            }
        }
    }

    function _domainSeparator() private view returns (bytes32) {
        return keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                block.chainid,
                address(this)
            )
        );
    }
}
