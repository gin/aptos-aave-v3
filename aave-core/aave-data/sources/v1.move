/// @title Aave Data V1
/// @author Aave
/// @notice Module that stores and provides access to Aave protocol configuration data
module aave_data::v1 {
    // imports
    // std
    use std::signer;
    use std::string;
    use std::string::{String, utf8};
    use std::vector;
    use aptos_std::smart_table;
    // locals
    use aave_config::error_config;

    // Global Constants
    /// @notice Prefix for aToken names
    const ATOKEN_NAME_PREFIX: vector<u8> = b"AAVE_A";
    /// @notice Prefix for aToken symbols
    const ATOKEN_SYMBOL_PREFIX: vector<u8> = b"AA";
    /// @notice Prefix for variable debt token names
    const VARTOKEN_NAME_PREFIX: vector<u8> = b"AAVE_V";
    /// @notice Prefix for variable debt token symbols
    const VARTOKEN_SYMBOL_PREFIX: vector<u8> = b"AV";

    // Structs
    /// @notice Main data structure to store all protocol configuration
    struct Data has key {
        /// @dev Price feed addresses for testnet assets
        price_feeds_testnet: smart_table::SmartTable<string::String, vector<u8>>,
        /// @dev Price feed addresses for mainnet assets
        price_feeds_mainnet: smart_table::SmartTable<string::String, vector<u8>>,
        /// @dev Underlying asset addresses for testnet
        underlying_assets_testnet: smart_table::SmartTable<string::String, address>,
        /// @dev Underlying asset addresses for mainnet
        underlying_assets_mainnet: smart_table::SmartTable<string::String, address>,
        /// @dev Reserve configurations for testnet
        reserves_config_testnet: smart_table::SmartTable<string::String, aave_data::v1_values::ReserveConfig>,
        /// @dev Reserve configurations for mainnet
        reserves_config_mainnet: smart_table::SmartTable<string::String, aave_data::v1_values::ReserveConfig>,
        /// @dev Interest rate strategies for testnet
        interest_rate_strategy_testnet: smart_table::SmartTable<string::String, aave_data::v1_values::InterestRateStrategy>,
        /// @dev Interest rate strategies for mainnet
        interest_rate_strategy_mainnet: smart_table::SmartTable<string::String, aave_data::v1_values::InterestRateStrategy>,
        /// @dev E-modes configuration for testnet
        emodes_testnet: smart_table::SmartTable<u256, aave_data::v1_values::EmodeConfig>,
        /// @dev E-modes configuration for mainnet
        emodes_mainnet: smart_table::SmartTable<u256, aave_data::v1_values::EmodeConfig>
    }

    // Private functions
    /// @dev Initializes the module with configuration data
    /// @param account The signer account that initializes the module
    fun init_module(account: &signer) {
        assert!(
            signer::address_of(account) == @aave_data,
            error_config::get_enot_pool_owner()
        );
        move_to(
            account,
            Data {
                price_feeds_testnet: aave_data::v1_values::build_price_feeds_testnet(),
                price_feeds_mainnet: aave_data::v1_values::build_price_feeds_mainnet(),
                underlying_assets_testnet: aave_data::v1_values::build_underlying_assets_testnet(),
                underlying_assets_mainnet: aave_data::v1_values::build_underlying_assets_mainnet(),
                reserves_config_testnet: aave_data::v1_values::build_reserve_config_testnet(),
                reserves_config_mainnet: aave_data::v1_values::build_reserve_config_mainnet(),
                interest_rate_strategy_testnet: aave_data::v1_values::build_interest_rate_strategy_testnet(),
                interest_rate_strategy_mainnet: aave_data::v1_values::build_interest_rate_strategy_mainnet(),
                emodes_testnet: aave_data::v1_values::build_emodes_testnet(),
                emodes_mainnet: aave_data::v1_values::build_emodes_mainnet()
            }
        );
    }

    // Public functions - Token naming
    /// @notice Constructs an aToken name from the underlying asset symbol
    /// @param underlying_asset_symbol The symbol of the underlying asset
    /// @return The aToken name
    public inline fun get_atoken_name(underlying_asset_symbol: String): String {
        let name = utf8(ATOKEN_NAME_PREFIX);
        string::append(&mut name, utf8(b"_"));
        string::append(&mut name, underlying_asset_symbol);
        name
    }

    /// @notice Constructs an aToken symbol from the underlying asset symbol
    /// @param underlying_asset_symbol The symbol of the underlying asset
    /// @return The aToken symbol
    public inline fun get_atoken_symbol(underlying_asset_symbol: String): String {
        let symbol = utf8(ATOKEN_SYMBOL_PREFIX);
        string::append(&mut symbol, utf8(b"_"));
        string::append(&mut symbol, underlying_asset_symbol);
        symbol
    }

    /// @notice Constructs a variable debt token name from the underlying asset symbol
    /// @param underlying_asset_symbol The symbol of the underlying asset
    /// @return The variable debt token name
    public inline fun get_vartoken_name(underlying_asset_symbol: String): String {
        let name = utf8(VARTOKEN_NAME_PREFIX);
        string::append(&mut name, utf8(b"_"));
        string::append(&mut name, underlying_asset_symbol);
        name
    }

    /// @notice Constructs a variable debt token symbol from the underlying asset symbol
    /// @param underlying_asset_symbol The symbol of the underlying asset
    /// @return The variable debt token symbol
    public inline fun get_vartoken_symbol(underlying_asset_symbol: String): String {
        let symbol = utf8(VARTOKEN_SYMBOL_PREFIX);
        string::append(&mut symbol, utf8(b"_"));
        string::append(&mut symbol, underlying_asset_symbol);
        symbol
    }

    /// @notice Gets the list of asset symbols for testnet
    /// @return Vector of asset symbols for testnet
    public inline fun get_asset_symbols_testnet(): &vector<string::String> acquires Data {
        &smart_table::keys(&borrow_global<Data>(@aave_pool).price_feeds_testnet)
    }

    /// @notice Gets the list of asset symbols for mainnet
    /// @return Vector of asset symbols for mainnet
    public inline fun get_asset_symbols_mainnet(): &vector<string::String> acquires Data {
        &smart_table::keys(&borrow_global<Data>(@aave_pool).price_feeds_mainnet)
    }

    // Public functions - Price feeds access
    /// @notice Gets the price feed mapping for testnet
    /// @return SmartTable mapping asset symbols to price feed addresses
    public inline fun get_price_feeds_tesnet():
        &smart_table::SmartTable<string::String, vector<u8>> acquires Data {
        &borrow_global<Data>(@aave_pool).price_feeds_testnet
    }

    /// @notice Gets the price feeds for testnet in normalized format (keys and values as separate vectors)
    /// @return Tuple of (asset symbols, price feed addresses)
    public fun get_price_feeds_testnet_normalized(): (vector<String>, vector<vector<u8>>) acquires Data {
        let table = &borrow_global<Data>(@aave_pool).price_feeds_testnet;
        let keys = smart_table::keys(table);
        let views = vector::empty<vector<u8>>();

        let i = 0;
        while (i < vector::length(&keys)) {
            let key = *vector::borrow(&keys, i);
            let val = *smart_table::borrow(table, key);
            vector::push_back(&mut views, val);
            i = i + 1;
        };
        (keys, views)
    }

    /// @notice Gets the price feed mapping for mainnet
    /// @return SmartTable mapping asset symbols to price feed addresses
    public inline fun get_price_feeds_mainnet():
        &smart_table::SmartTable<string::String, vector<u8>> acquires Data {
        &borrow_global<Data>(@aave_pool).price_feeds_mainnet
    }

    /// @notice Gets the price feeds for mainnet in normalized format (keys and values as separate vectors)
    /// @return Tuple of (asset symbols, price feed addresses)
    public fun get_price_feeds_mainnet_normalized(): (vector<String>, vector<vector<u8>>) acquires Data {
        let table = &borrow_global<Data>(@aave_pool).price_feeds_mainnet;
        let keys = smart_table::keys(table);
        let views = vector::empty<vector<u8>>();

        let i = 0;
        while (i < vector::length(&keys)) {
            let key = *vector::borrow(&keys, i);
            let val = *smart_table::borrow(table, key);
            vector::push_back(&mut views, val);
            i = i + 1;
        };
        (keys, views)
    }

    // Public functions - Underlying assets access
    /// @notice Gets the underlying assets mapping for testnet
    /// @return SmartTable mapping asset symbols to underlying asset addresses
    public inline fun get_underlying_assets_testnet():
        &smart_table::SmartTable<string::String, address> acquires Data {
        &borrow_global<Data>(@aave_pool).underlying_assets_testnet
    }

    /// @notice Gets the underlying assets for testnet in normalized format (keys and values as separate vectors)
    /// @return Tuple of (asset symbols, underlying asset addresses)
    public fun get_underlying_assets_testnet_normalized(): (vector<String>, vector<address>) acquires Data {
        let table = &borrow_global<Data>(@aave_pool).underlying_assets_testnet;
        let keys = smart_table::keys(table);
        let views = vector::empty<address>();

        let i = 0;
        while (i < vector::length(&keys)) {
            let key = *vector::borrow(&keys, i);
            let val = *smart_table::borrow(table, key);
            vector::push_back(&mut views, val);
            i = i + 1;
        };
        (keys, views)
    }

    /// @notice Gets the underlying assets mapping for mainnet
    /// @return SmartTable mapping asset symbols to underlying asset addresses
    public inline fun get_underlying_assets_mainnet():
        &smart_table::SmartTable<string::String, address> acquires Data {
        &borrow_global<Data>(@aave_pool).underlying_assets_mainnet
    }

    /// @notice Gets the underlying assets for mainnet in normalized format (keys and values as separate vectors)
    /// @return Tuple of (asset symbols, underlying asset addresses)
    public fun get_underlying_assets_mainnet_normalized(): (vector<String>, vector<address>) acquires Data {
        let table = &borrow_global<Data>(@aave_pool).underlying_assets_mainnet;
        let keys = smart_table::keys(table);
        let views = vector::empty<address>();

        let i = 0;
        while (i < vector::length(&keys)) {
            let key = *vector::borrow(&keys, i);
            let val = *smart_table::borrow(table, key);
            vector::push_back(&mut views, val);
            i = i + 1;
        };
        (keys, views)
    }

    // Public functions - Reserve configs access
    /// @notice Gets the reserve configurations mapping for testnet
    /// @return SmartTable mapping asset symbols to reserve configurations
    public inline fun get_reserves_config_testnet():
        &smart_table::SmartTable<string::String, aave_data::v1_values::ReserveConfig> acquires Data {
        &borrow_global<Data>(@aave_pool).reserves_config_testnet
    }

    /// @notice Gets the reserve configurations for testnet in normalized format (keys and values as separate vectors)
    /// @return Tuple of (asset symbols, reserve configurations)
    public fun get_reserves_config_testnet_normalized(): (
        vector<String>, vector<aave_data::v1_values::ReserveConfig>
    ) acquires Data {
        let table = &borrow_global<Data>(@aave_pool).reserves_config_testnet;
        let keys = smart_table::keys(table);
        let views = vector::empty<aave_data::v1_values::ReserveConfig>();

        let i = 0;
        while (i < vector::length(&keys)) {
            let key = *vector::borrow(&keys, i);
            let val = *smart_table::borrow(table, key);
            vector::push_back(&mut views, val);
            i = i + 1;
        };
        (keys, views)
    }

    /// @notice Gets the reserve configurations mapping for mainnet
    /// @return SmartTable mapping asset symbols to reserve configurations
    public inline fun get_reserves_config_mainnet():
        &smart_table::SmartTable<string::String, aave_data::v1_values::ReserveConfig> acquires Data {
        &borrow_global<Data>(@aave_pool).reserves_config_mainnet
    }

    /// @notice Gets the reserve configurations for mainnet in normalized format (keys and values as separate vectors)
    /// @return Tuple of (asset symbols, reserve configurations)
    public fun get_reserves_config_mainnet_normalized(): (
        vector<String>, vector<aave_data::v1_values::ReserveConfig>
    ) acquires Data {
        let table = &borrow_global<Data>(@aave_pool).reserves_config_mainnet;
        let keys = smart_table::keys(table);
        let views = vector::empty<aave_data::v1_values::ReserveConfig>();

        let i = 0;
        while (i < vector::length(&keys)) {
            let key = *vector::borrow(&keys, i);
            let val = *smart_table::borrow(table, key);
            vector::push_back(&mut views, val);
            i = i + 1;
        };
        (keys, views)
    }

    // Public functions - Interest rate strategies access
    /// @notice Gets the interest rate strategies mapping for testnet
    /// @return SmartTable mapping asset symbols to interest rate strategies
    public inline fun get_interest_rate_strategy_testnet():
        &smart_table::SmartTable<string::String, aave_data::v1_values::InterestRateStrategy> acquires Data {
        &borrow_global<Data>(@aave_pool).interest_rate_strategy_testnet
    }

    /// @notice Gets the interest rate strategies for testnet in normalized format (keys and values as separate vectors)
    /// @return Tuple of (asset symbols, interest rate strategies)
    public fun get_interest_rate_strategy_testnet_normalized(): (
        vector<String>, vector<aave_data::v1_values::InterestRateStrategy>
    ) acquires Data {
        let table = &borrow_global<Data>(@aave_pool).interest_rate_strategy_testnet;
        let keys = smart_table::keys(table);
        let views = vector::empty<aave_data::v1_values::InterestRateStrategy>();

        let i = 0;
        while (i < vector::length(&keys)) {
            let key = *vector::borrow(&keys, i);
            let val = *smart_table::borrow(table, key);
            vector::push_back(&mut views, val);
            i = i + 1;
        };
        (keys, views)
    }

    /// @notice Gets the interest rate strategies mapping for mainnet
    /// @return SmartTable mapping asset symbols to interest rate strategies
    public inline fun get_interest_rate_strategy_mainnet():
        &smart_table::SmartTable<string::String, aave_data::v1_values::InterestRateStrategy> acquires Data {
        &borrow_global<Data>(@aave_pool).interest_rate_strategy_mainnet
    }

    /// @notice Gets the interest rate strategies for mainnet in normalized format (keys and values as separate vectors)
    /// @return Tuple of (asset symbols, interest rate strategies)
    public fun get_interest_rate_strategy_mainnet_normalized(): (
        vector<String>, vector<aave_data::v1_values::InterestRateStrategy>
    ) acquires Data {
        let table = &borrow_global<Data>(@aave_pool).interest_rate_strategy_mainnet;
        let keys = smart_table::keys(table);
        let views = vector::empty<aave_data::v1_values::InterestRateStrategy>();

        let i = 0;
        while (i < vector::length(&keys)) {
            let key = *vector::borrow(&keys, i);
            let val = *smart_table::borrow(table, key);
            vector::push_back(&mut views, val);
            i = i + 1;
        };
        (keys, views)
    }

    // Public functions - E-modes access
    /// @notice Gets the E-modes mapping for mainnet
    /// @return SmartTable mapping E-mode IDs to E-mode configurations
    public inline fun get_emodes_mainnet():
        &smart_table::SmartTable<u256, aave_data::v1_values::EmodeConfig> acquires Data {
        &borrow_global<Data>(@aave_pool).emodes_mainnet
    }

    /// @notice Gets the E-modes for mainnet in normalized format (keys and values as separate vectors)
    /// @return Tuple of (E-mode IDs, E-mode configurations)
    public fun get_emodes_mainnet_normalized(): (
        vector<u256>, vector<aave_data::v1_values::EmodeConfig>
    ) acquires Data {
        let emodes = &borrow_global<Data>(@aave_pool).emodes_mainnet;
        let keys = smart_table::keys(emodes);
        let configs = vector::empty<aave_data::v1_values::EmodeConfig>();

        let i = 0;
        while (i < vector::length(&keys)) {
            let key = *vector::borrow(&keys, i);
            let config = *smart_table::borrow(emodes, key);
            vector::push_back(&mut configs, config);
            i = i + 1;
        };
        (keys, configs)
    }

    /// @notice Gets the E-modes mapping for testnet
    /// @return SmartTable mapping E-mode IDs to E-mode configurations
    public inline fun get_emodes_testnet():
        &smart_table::SmartTable<u256, aave_data::v1_values::EmodeConfig> acquires Data {
        &borrow_global<Data>(@aave_pool).emodes_testnet
    }

    /// @notice Gets the E-modes for testnet in normalized format (keys and values as separate vectors)
    /// @return Tuple of (E-mode IDs, E-mode configurations)
    public fun get_emode_testnet_normalized(): (
        vector<u256>, vector<aave_data::v1_values::EmodeConfig>
    ) acquires Data {
        let emodes = &borrow_global<Data>(@aave_pool).emodes_testnet;
        let keys = smart_table::keys(emodes);
        let configs = vector::empty<aave_data::v1_values::EmodeConfig>();

        let i = 0;
        while (i < vector::length(&keys)) {
            let key = *vector::borrow(&keys, i);
            let config = *smart_table::borrow(emodes, key);
            vector::push_back(&mut configs, config);
            i = i + 1;
        };
        (keys, configs)
    }
}
