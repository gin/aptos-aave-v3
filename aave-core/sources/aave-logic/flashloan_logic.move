/// @title Flashloan Logic Module
/// @author Aave
/// @notice Implements the logic for the flash loans
module aave_pool::flashloan_logic {
    // imports
    use std::signer;
    use std::vector;
    use aptos_framework::event;

    use aave_acl::acl_manage;
    use aave_config::error_config::Self;
    use aave_config::user_config::Self;
    use aave_math::math_utils;
    use aave_math::wad_ray_math;
    use aave_pool::fee_manager;
    use aave_pool::pool_logic;

    use aave_pool::a_token_factory;
    use aave_pool::borrow_logic;
    use aave_pool::fungible_asset_manager;
    use aave_pool::pool;
    use aave_pool::validation_logic::Self;

    // Events
    #[event]
    /// @dev Emitted on pay_flash_loan_complex() and handle_flash_loan_repayment()
    /// @param target The address of the flash loan receiver contract
    /// @param initiator The address initiating the flash loan
    /// @param asset The address of the asset being flash borrowed
    /// @param amount The amount flash borrowed
    /// @param interest_rate_mode The flashloan mode: 0 for regular flashloan, 2 for Variable debt
    /// @param premium The fee flash borrowed
    /// @param referral_code The referral code used
    struct FlashLoan has store, drop {
        target: address,
        initiator: address,
        asset: address,
        amount: u256,
        interest_rate_mode: u8,
        premium: u256,
        referral_code: u16
    }

    // Structs
    /// @notice Helper struct for internal variables used in the `execute_flash_loan_complex` and `execute_flash_loan_simple` function
    /// @dev Holds temporary data during flash loan execution
    struct FlashLoanLocalVars has copy, drop {
        sender: address,
        receiver: address,
        i: u256,
        current_asset: address,
        current_amount: u256,
        total_premium: u256,
        flashloan_premium_total: u256,
        flashloan_premium_to_protocol: u256
    }

    /// @notice Receipt for simple flash loans containing all information about the flash loan
    /// @dev Used to track and validate flash loan repayments
    struct SimpleFlashLoansReceipt {
        sender: address,
        receiver: address,
        i: u256,
        current_asset: address,
        current_amount: u256,
        total_premium: u256,
        flashloan_premium_total: u256,
        flashloan_premium_to_protocol: u256,
        referral_code: u16,
        on_behalf_of: address
    }

    /// @notice Receipt for complex flash loans containing all information about the flash loan
    /// @dev Used to track and validate complex flash loan repayments with different interest rate modes
    struct ComplexFlashLoansReceipt {
        sender: address,
        receiver: address,
        i: u256,
        current_asset: address,
        current_amount: u256,
        total_premium: u256,
        flashloan_premium_total: u256,
        flashloan_premium_to_protocol: u256,
        referral_code: u16,
        interest_rate_mode: u8,
        on_behalf_of: address
    }

    /// @notice Parameters for flash loan repayment
    /// @dev Used to pass flash loan repayment details to the handle_flash_loan_repayment function
    struct FlashLoanRepaymentParams has drop {
        amount: u256,
        total_premium: u256,
        flashloan_premium_to_protocol: u256,
        asset: address,
        receiver_address: address,
        referral_code: u16
    }

    // Public functions
    /// @notice Allows smartcontracts to access the liquidity of the pool within one transaction,
    /// as long as the amount taken plus a fee is returned.
    /// @dev IMPORTANT There are security concerns for developers of flashloan receiver contracts that must be kept
    /// into consideration. For further details please visit https://docs.aave.com/developers/
    /// @param initiator The signer account of the flash loan initiator
    /// @param receiver_address The address of the contract receiving the funds
    /// @param assets The addresses of the assets being flash-borrowed
    /// @param amounts The amounts of the assets being flash-borrowed
    /// @param interest_rate_modes Types of the debt to open if the flash loan is not returned:
    ///   0 -> Don't open any debt, just revert if funds can't be transferred from the receiver
    ///   2 -> Open debt at variable rate for the value of the amount flash-borrowed to the `on_behalf_of` address
    /// @param on_behalf_of The address  that will receive the debt in the case of using on `interest_rate_modes` 2, on_behalf_of Should be the account address
    /// @param referral_code The code used to register the integrator originating the operation, for potential rewards.
    /// @return the receipt for the complex flashloan
    public fun flash_loan(
        initiator: &signer,
        receiver_address: address,
        assets: vector<address>,
        amounts: vector<u256>,
        interest_rate_modes: vector<u8>,
        on_behalf_of: address,
        referral_code: u16
    ): vector<ComplexFlashLoansReceipt> {
        execute_flash_loan_complex(
            initiator,
            receiver_address,
            assets,
            amounts,
            interest_rate_modes,
            on_behalf_of,
            referral_code,
            (pool::get_flashloan_premium_to_protocol() as u256),
            (pool::get_flashloan_premium_total() as u256),
            acl_manage::is_flash_borrower(signer::address_of(initiator))
        )
    }

    /// @notice Allows smartcontracts to access the liquidity of the pool within one transaction,
    /// as long as the amount taken plus a fee is returned.
    /// @dev IMPORTANT There are security concerns for developers of flashloan receiver contracts that must be kept
    /// into consideration. For further details please visit https://docs.aave.com/developers/
    /// @param initiator The signer account of the flash loan initiator
    /// @param receiver_address The address of the contract receiving the funds
    /// @param asset The address of the asset being flash-borrowed
    /// @param amount The amount of the asset being flash-borrowed
    /// @param referral_code The code used to register the integrator originating the operation, for potential rewards.
    /// @return the receipt for the simple flashloan
    public fun flash_loan_simple(
        initiator: &signer,
        receiver_address: address,
        asset: address,
        amount: u256,
        referral_code: u16
    ): SimpleFlashLoansReceipt {
        execute_flash_loan_simple(
            initiator,
            receiver_address,
            asset,
            amount,
            referral_code,
            (pool::get_flashloan_premium_to_protocol() as u256),
            (pool::get_flashloan_premium_total() as u256)
        )
    }

    /// @notice Repays flashloaned assets + premium
    /// @dev Will pull the amount + premium from the receiver
    /// @param flash_loan_receiver The signer account of the flash loan receiver
    /// @param flashloan_receipts The receipts of the flashloaned assets
    public fun pay_flash_loan_complex(
        flash_loan_receiver: &signer, flashloan_receipts: vector<ComplexFlashLoansReceipt>
    ) {
        // get the payer account
        let flash_loan_receiver_address = signer::address_of(flash_loan_receiver);

        // destroy all receipts and handle their repayment
        vector::destroy(
            flashloan_receipts,
            |flashloan| {
                let ComplexFlashLoansReceipt {
                    sender,
                    receiver,
                    i: _,
                    current_asset,
                    current_amount,
                    total_premium,
                    flashloan_premium_total: _,
                    flashloan_premium_to_protocol,
                    referral_code,
                    interest_rate_mode,
                    on_behalf_of
                } = flashloan;

                // check the signer is the receiver that the receipt was issued for
                assert!(
                    flash_loan_receiver_address == receiver,
                    error_config::get_flashloan_payer_not_receiver()
                );

                if (interest_rate_mode == user_config::get_interest_rate_mode_none()) {
                    // do flashloan repayment
                    let repayment_params = FlashLoanRepaymentParams {
                        amount: current_amount,
                        total_premium,
                        flashloan_premium_to_protocol,
                        asset: current_asset,
                        receiver_address: receiver,
                        referral_code
                    };
                    handle_flash_loan_repayment(
                        flash_loan_receiver, &repayment_params, sender
                    );
                } else {
                    // collect a gas fee so no free borrow can be opened.
                    // when this branch is reached, the premium is already 0
                    fee_manager::collect_apt_fee(flash_loan_receiver, current_asset);

                    // If the user chose to not return the funds, the system checks if there is enough collateral and
                    // eventually opens a debt position
                    borrow_logic::internal_borrow(
                        sender, // flash loan initiator
                        current_asset, // asset
                        current_amount, // amount
                        interest_rate_mode,
                        referral_code, // referral_code
                        on_behalf_of, // on behalf of,
                        false // release_underlying
                    );
                    event::emit(
                        FlashLoan {
                            target: receiver,
                            initiator: sender,
                            asset: current_asset,
                            amount: current_amount,
                            interest_rate_mode,
                            premium: 0,
                            referral_code
                        }
                    );
                };
            }
        )
    }

    /// @notice Repays flashloaned assets + premium
    /// @dev Will pull the amount + premium from the receiver
    /// @param flash_loan_receiver The signer account of flash loan receiver
    /// @param flashloan_receipt The receipt of the flashloaned asset
    public fun pay_flash_loan_simple(
        flash_loan_receiver: &signer, flashloan_receipt: SimpleFlashLoansReceipt
    ) {
        // destructure the receipt
        let SimpleFlashLoansReceipt {
            sender,
            receiver,
            i: _,
            current_asset,
            current_amount,
            total_premium,
            flashloan_premium_total: _,
            flashloan_premium_to_protocol,
            referral_code,
            on_behalf_of: _
        } = flashloan_receipt;

        // check the signer is the receiver that the receipt was issued for
        assert!(
            signer::address_of(flash_loan_receiver) == receiver,
            error_config::get_flashloan_payer_not_receiver()
        );

        // do flashloan repayment
        let repayment_params = FlashLoanRepaymentParams {
            amount: current_amount,
            total_premium,
            flashloan_premium_to_protocol,
            asset: current_asset,
            receiver_address: receiver,
            referral_code
        };
        handle_flash_loan_repayment(flash_loan_receiver, &repayment_params, sender);
    }

    // Getter functions for SimpleFlashLoansReceipt
    /// @notice Returns the simple flashloan receipt sender
    /// @param receipt The simple flashloan receipt received
    /// @return the address of the sender inside the simple flashloan receipt
    public fun get_simple_flashloan_receipt_sender(
        receipt: &SimpleFlashLoansReceipt
    ): address {
        receipt.sender
    }

    /// @notice Returns the simple flashloan receipt receiver
    /// @param receipt The simple flashloan receipt received
    /// @return the address of the receiver inside the simple flashloan receipt
    public fun get_simple_flashloan_receipt_receiver(
        receipt: &SimpleFlashLoansReceipt
    ): address {
        receipt.receiver
    }

    /// @notice Returns the simple flashloan receipt index
    /// @param receipt The simple flashloan receipt received
    /// @return the simple flashloan receipt index
    public fun get_simple_flashloan_receipt_index(
        receipt: &SimpleFlashLoansReceipt
    ): u256 {
        receipt.i
    }

    /// @notice Returns the simple flashloan receipt current asset
    /// @param receipt The simple flashloan receipt received
    /// @return the simple flashloan receipt asset
    public fun get_simple_flashloan_current_asset(
        receipt: &SimpleFlashLoansReceipt
    ): address {
        receipt.current_asset
    }

    /// @notice Returns the simple flashloan receipt current amount
    /// @param receipt The simple flashloan receipt received
    /// @return the simple flashloan receipt amount
    public fun get_simple_flashloan_current_amount(
        receipt: &SimpleFlashLoansReceipt
    ): u256 {
        receipt.current_amount
    }

    /// @notice Returns the simple flashloan receipt total premium
    /// @param receipt The simple flashloan receipt received
    /// @return the simple flashloan receipt total premium
    public fun get_simple_flashloan_total_premium(
        receipt: &SimpleFlashLoansReceipt
    ): u256 {
        receipt.total_premium
    }

    /// @notice Returns the simple flashloan receipt premium total
    /// @param receipt The simple flashloan receipt received
    /// @return the simple flashloan receipt premium total
    public fun get_simple_flashloan_premium_total(
        receipt: &SimpleFlashLoansReceipt
    ): u256 {
        receipt.flashloan_premium_total
    }

    /// @notice Returns the simple flashloan receipt premium to protocol
    /// @param receipt The simple flashloan receipt received
    /// @return the simple flashloan receipt premium to protocol
    public fun get_simple_flashloan_premium_to_protocol(
        receipt: &SimpleFlashLoansReceipt
    ): u256 {
        receipt.flashloan_premium_to_protocol
    }

    /// @notice Returns the simple flashloan receipt referral code
    /// @param receipt The simple flashloan receipt received
    /// @return the simple flashloan receipt referral code
    public fun get_simple_flashloan_referral_code(
        receipt: &SimpleFlashLoansReceipt
    ): u16 {
        receipt.referral_code
    }

    /// @notice Returns the simple flashloan receipt on behalf of
    /// @param receipt The simple flashloan receipt received
    /// @return the simple flashloan receipt on behalf of
    public fun get_simple_flashloan_on_behalf_of(
        receipt: &SimpleFlashLoansReceipt
    ): address {
        receipt.on_behalf_of
    }

    // Getter functions for ComplexFlashLoansReceipt
    /// @notice Returns the complex flashloan receipt sender
    /// @param receipt The complex flashloan receipt received
    /// @return the complex flashloan receipt sender
    public fun get_complex_flashloan_receipt_sender(
        receipt: &ComplexFlashLoansReceipt
    ): address {
        receipt.sender
    }

    /// @notice Returns the complex flashloan receipt receiver
    /// @param receipt The complex flashloan receipt received
    /// @return the complex flashloan receipt receiver
    public fun get_complex_flashloan_receipt_receiver(
        receipt: &ComplexFlashLoansReceipt
    ): address {
        receipt.receiver
    }

    /// @notice Returns the complex flashloan receipt index
    /// @param receipt The complex flashloan receipt received
    /// @return the complex flashloan receipt index
    public fun get_complex_flashloan_receipt_index(
        receipt: &ComplexFlashLoansReceipt
    ): u256 {
        receipt.i
    }

    /// @notice Returns the complex flashloan receipt current asset
    /// @param receipt The complex flashloan receipt received
    /// @return the complex flashloan receipt asset
    public fun get_complex_flashloan_current_asset(
        receipt: &ComplexFlashLoansReceipt
    ): address {
        receipt.current_asset
    }

    /// @notice Returns the complex flashloan receipt current amount
    /// @param receipt The complex flashloan receipt received
    /// @return the complex flashloan receipt amount
    public fun get_complex_flashloan_current_amount(
        receipt: &ComplexFlashLoansReceipt
    ): u256 {
        receipt.current_amount
    }

    /// @notice Returns the complex flashloan receipt total premium
    /// @param receipt The complex flashloan receipt received
    /// @return the complex flashloan receipt total premium
    public fun get_complex_flashloan_total_premium(
        receipt: &ComplexFlashLoansReceipt
    ): u256 {
        receipt.total_premium
    }

    /// @notice Returns the complex flashloan receipt premium total
    /// @param receipt The complex flashloan receipt received
    /// @return the complex flashloan receipt total premium
    public fun get_complex_flashloan_premium_total(
        receipt: &ComplexFlashLoansReceipt
    ): u256 {
        receipt.flashloan_premium_total
    }

    /// @notice Returns the complex flashloan receipt premium to protocol
    /// @param receipt The complex flashloan receipt received
    /// @return the complex flashloan receipt premium to protocol
    public fun get_complex_flashloan_premium_to_protocol(
        receipt: &ComplexFlashLoansReceipt
    ): u256 {
        receipt.flashloan_premium_to_protocol
    }

    /// @notice Returns the complex flashloan receipt referral code
    /// @param receipt The complex flashloan receipt received
    /// @return the complex flashloan receipt referrral code
    public fun get_complex_flashloan_referral_code(
        receipt: &ComplexFlashLoansReceipt
    ): u16 {
        receipt.referral_code
    }

    /// @notice Returns the complex flashloan receipt interest rate mode
    /// @param receipt The complex flashloan receipt received
    /// @return the complex flashloan receipt interest rate mode
    public fun get_complex_flashloan_interest_rate_mode(
        receipt: &ComplexFlashLoansReceipt
    ): u8 {
        receipt.interest_rate_mode
    }

    /// @notice Returns the complex flashloan receipt on behalf of
    /// @param receipt The complex flashloan receipt received
    /// @return the complex flashloan receipt on behalf of
    public fun get_complex_flashloan_on_behalf_of(
        receipt: &ComplexFlashLoansReceipt
    ): address {
        receipt.on_behalf_of
    }

    // Private functions
    /// @notice Executes complex flash loans for multiple assets with different interest rate modes
    /// @dev Handles borrowing multiple assets in a single transaction with option to incur debt
    /// @param initiator The signer account of the flash loan initiator
    /// @param receiver_address The address of the contract receiving the funds
    /// @param assets The addresses of the assets being flash-borrowed
    /// @param amounts The amounts of the assets being flash-borrowed
    /// @param interest_rate_modes Types of the debt to open if the flash loan is not returned
    /// @param on_behalf_of The address that will receive the debt if incurred
    /// @param referral_code The code used to register the integrator originating the operation
    /// @param flash_loan_premium_to_protocol The portion of the premium that goes to the protocol
    /// @param flash_loan_premium_total The total premium for the flash loan
    /// @param is_authorized_flash_borrower Whether the initiator is an authorized flash borrower
    /// @return Vector of receipts for the complex flash loans
    fun execute_flash_loan_complex(
        initiator: &signer,
        receiver_address: address,
        assets: vector<address>,
        amounts: vector<u256>,
        interest_rate_modes: vector<u8>,
        on_behalf_of: address,
        referral_code: u16,
        flash_loan_premium_to_protocol: u256,
        flash_loan_premium_total: u256,
        is_authorized_flash_borrower: bool
    ): vector<ComplexFlashLoansReceipt> {
        // get signer account
        let initiator_address = signer::address_of(initiator);
        assert!(
            initiator_address == on_behalf_of,
            error_config::get_esigner_and_on_behalf_of_no_same()
        );

        // validate flashloans logic
        validation_logic::validate_flashloan_complex(
            &assets, &amounts, &interest_rate_modes
        );

        // validate interest rates
        assert!(
            !vector::any(
                &interest_rate_modes,
                |interest_rate| {
                    let legitimate_interes_rate =
                        *interest_rate == user_config::get_interest_rate_mode_none()
                            || *interest_rate
                                == user_config::get_interest_rate_mode_variable();
                    !legitimate_interes_rate
                }
            ),
            error_config::get_einvalid_interest_rate_mode_selected()
        );

        let flashloan_premium_total =
            if (is_authorized_flash_borrower) { 0 }
            else {
                flash_loan_premium_total
            };
        let flashloan_premium_to_protocol =
            if (is_authorized_flash_borrower) { 0 }
            else {
                flash_loan_premium_to_protocol
            };
        let flashloans = vector<FlashLoanLocalVars>[];

        for (i in 0..vector::length(&assets)) {
            let asset = *vector::borrow(&assets, i);
            let amount = *vector::borrow(&amounts, i);

            // calculate premiums
            let total_premium =
                if (*vector::borrow(&interest_rate_modes, i)
                    == user_config::get_interest_rate_mode_none()) {
                    math_utils::percent_mul(amount, flashloan_premium_total)
                } else { 0 };

            let flashloan_vars = FlashLoanLocalVars {
                sender: initiator_address,
                receiver: receiver_address,
                i: (i as u256),
                current_asset: asset,
                current_amount: amount,
                total_premium,
                flashloan_premium_total,
                flashloan_premium_to_protocol
            };

            // update virtual balance if needed
            let reserve_data = pool::get_reserve_data(asset);
            let virtual_balance =
                pool::get_reserve_virtual_underlying_balance(reserve_data);
            virtual_balance = virtual_balance - (amount as u128);
            pool::set_reserve_virtual_underlying_balance(reserve_data, virtual_balance);

            // transfer the underlying to the receiver
            transfer_underlying_to(&flashloan_vars);

            // save the taken flashloan
            vector::push_back(&mut flashloans, flashloan_vars);
        };

        let flashloan_receipts = vector::map<FlashLoanLocalVars, ComplexFlashLoansReceipt>(
            flashloans,
            |flashloan| {
                let flashloan: FlashLoanLocalVars = flashloan;
                let interest_rate_mode =
                    *vector::borrow(&interest_rate_modes, (flashloan.i as u64));
                create_complex_flashloan_receipt(
                    &flashloan,
                    initiator_address,
                    referral_code,
                    on_behalf_of,
                    interest_rate_mode
                )
            }
        );

        flashloan_receipts
    }

    /// @notice Executes a simple flash loan for a single asset
    /// @dev Handles borrowing a single asset with standard flash loan functionality
    /// @param initiator The signer account of the flash loan initiator
    /// @param receiver_address The address of the contract receiving the funds
    /// @param asset The address of the asset being flash-borrowed
    /// @param amount The amount of the asset being flash-borrowed
    /// @param referral_code The code used to register the integrator originating the operation
    /// @param flashloan_premium_to_protocol The portion of the premium that goes to the protocol
    /// @param flashloan_premium_total The total premium for the flash loan
    /// @return Receipt for the simple flash loan
    fun execute_flash_loan_simple(
        initiator: &signer,
        receiver_address: address,
        asset: address,
        amount: u256,
        referral_code: u16,
        flashloan_premium_to_protocol: u256,
        flashloan_premium_total: u256
    ): SimpleFlashLoansReceipt {
        // sender account address
        let initiator_address = signer::address_of(initiator);

        // get the reserve data
        let reserve_data = pool::get_reserve_data(asset);

        // validate flashloan logic
        validation_logic::validate_flashloan_simple(reserve_data, amount);

        // create flashloan
        let flashloan = FlashLoanLocalVars {
            sender: initiator_address,
            receiver: receiver_address,
            i: 0,
            current_asset: asset,
            current_amount: amount,
            total_premium: math_utils::percent_mul(amount, flashloan_premium_total),
            flashloan_premium_total,
            flashloan_premium_to_protocol
        };

        // update virtual balance if needed
        let virtual_balance = pool::get_reserve_virtual_underlying_balance(reserve_data);
        virtual_balance = virtual_balance - (amount as u128);
        pool::set_reserve_virtual_underlying_balance(reserve_data, virtual_balance);

        // transfer the underlying to the receiver
        transfer_underlying_to(&flashloan);

        // create and return the flashloan receipt
        let flashloan_receipt =
            create_simple_flashloan_receipt(
                &flashloan,
                initiator_address,
                referral_code,
                receiver_address
            );

        flashloan_receipt
    }

    /// @notice Creates a receipt for a simple flash loan
    /// @dev Packages flash loan data into a SimpleFlashLoansReceipt for tracking
    /// @param flashloan The flash loan local variables
    /// @param sender The address of the flash loan sender
    /// @param referral_code The referral code used for the flash loan
    /// @param on_behalf_of The address that will receive debt if incurred
    /// @return A new SimpleFlashLoansReceipt
    fun create_simple_flashloan_receipt(
        flashloan: &FlashLoanLocalVars,
        sender: address,
        referral_code: u16,
        on_behalf_of: address
    ): SimpleFlashLoansReceipt {
        SimpleFlashLoansReceipt {
            sender,
            receiver: flashloan.receiver,
            i: flashloan.i,
            current_asset: flashloan.current_asset,
            current_amount: flashloan.current_amount,
            total_premium: flashloan.total_premium,
            flashloan_premium_total: flashloan.flashloan_premium_total,
            flashloan_premium_to_protocol: flashloan.flashloan_premium_to_protocol,
            referral_code,
            on_behalf_of
        }
    }

    /// @notice Creates a receipt for a complex flash loan
    /// @dev Packages flash loan data into a ComplexFlashLoansReceipt for tracking
    /// @param flashloan The flash loan local variables
    /// @param sender The address of the flash loan sender
    /// @param referral_code The referral code used for the flash loan
    /// @param on_behalf_of The address that will receive debt if incurred
    /// @param interest_rate_mode The interest rate mode for potential debt
    /// @return A new ComplexFlashLoansReceipt
    fun create_complex_flashloan_receipt(
        flashloan: &FlashLoanLocalVars,
        sender: address,
        referral_code: u16,
        on_behalf_of: address,
        interest_rate_mode: u8
    ): ComplexFlashLoansReceipt {
        ComplexFlashLoansReceipt {
            sender,
            receiver: flashloan.receiver,
            i: flashloan.i,
            current_asset: flashloan.current_asset,
            current_amount: flashloan.current_amount,
            total_premium: flashloan.total_premium,
            flashloan_premium_total: flashloan.flashloan_premium_total,
            flashloan_premium_to_protocol: flashloan.flashloan_premium_to_protocol,
            referral_code,
            on_behalf_of,
            interest_rate_mode
        }
    }

    /// @notice Transfers the underlying asset to the flash loan receiver
    /// @dev Uses a_token_factory to transfer the asset
    /// @param flashloan_vars The flash loan local variables containing transfer details
    fun transfer_underlying_to(flashloan_vars: &FlashLoanLocalVars) {
        let reserve_data = pool::get_reserve_data(flashloan_vars.current_asset);
        let a_token_address = pool::get_reserve_a_token_address(reserve_data);
        a_token_factory::transfer_underlying_to(
            flashloan_vars.receiver, flashloan_vars.current_amount, a_token_address
        )
    }

    /// @notice Handles repayment of flashloaned assets + premium
    /// @dev Will pull the amount + premium from the receiver, so must have approved pool
    /// @param flash_loan_receiver The signer account of flash loan receiver
    /// @param repayment_params The additional parameters needed to execute the repayment function
    /// @param sender Flash loan initiators.
    fun handle_flash_loan_repayment(
        flash_loan_receiver: &signer,
        repayment_params: &FlashLoanRepaymentParams,
        sender: address
    ) {
        // get the reserve data
        let reserve_data = pool::get_reserve_data(repayment_params.asset);
        let reserve_cache = pool_logic::cache(reserve_data);
        let a_token_address = pool::get_reserve_a_token_address(reserve_data);

        // compute amount plus premiums
        let premium_to_protocol =
            math_utils::percent_mul(
                repayment_params.total_premium,
                repayment_params.flashloan_premium_to_protocol
            );
        let premium_to_lp = repayment_params.total_premium - premium_to_protocol;
        let amount_plus_premium = repayment_params.amount
            + repayment_params.total_premium;

        // update the pool state
        pool_logic::update_state(reserve_data, &mut reserve_cache);

        // update liquidity index
        let a_token_total_supply = a_token_factory::total_supply(a_token_address);
        let reserve_accrued_to_treasury =
            pool::get_reserve_accrued_to_treasury(reserve_data);
        let total_liquidity =
            a_token_total_supply
                + wad_ray_math::ray_mul(
                    reserve_accrued_to_treasury,
                    pool_logic::get_next_liquidity_index(&reserve_cache)
                );
        let next_liquidity_index =
            pool::cumulate_to_liquidity_index(
                reserve_data, total_liquidity, premium_to_lp
            );
        // update reserve cache next liquidity index
        pool_logic::set_next_liquidity_index(&mut reserve_cache, next_liquidity_index);

        // update accrued to treasury
        let new_reserve_accrued_to_treasury =
            reserve_accrued_to_treasury
                + wad_ray_math::ray_div(premium_to_protocol, next_liquidity_index);
        pool::set_reserve_accrued_to_treasury(
            reserve_data, new_reserve_accrued_to_treasury
        );

        // update pool interest rates
        pool_logic::update_interest_rates_and_virtual_balance(
            reserve_data,
            &reserve_cache,
            repayment_params.asset,
            amount_plus_premium,
            0
        );

        // transfer underlying tokens
        let a_token_account_address =
            a_token_factory::get_token_account_address(a_token_address);
        fungible_asset_manager::transfer(
            flash_loan_receiver,
            a_token_account_address,
            (amount_plus_premium as u64),
            repayment_params.asset
        );

        // handle the a token repayment
        a_token_factory::handle_repayment(
            repayment_params.receiver_address,
            repayment_params.receiver_address,
            amount_plus_premium,
            a_token_address
        );

        event::emit(
            FlashLoan {
                target: repayment_params.receiver_address,
                initiator: sender,
                asset: repayment_params.asset,
                amount: repayment_params.amount,
                interest_rate_mode: user_config::get_interest_rate_mode_none(),
                premium: repayment_params.total_premium,
                referral_code: repayment_params.referral_code
            }
        )
    }
}
