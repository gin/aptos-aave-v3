// @title ACL Admin Setup Script
// @author Aave
// @notice Script to initialize and set up administrators for the Aave ACL system
script {
    // imports
    // std
    use std::signer;
    use std::vector;
    // locals
    use aave_acl::acl_manage::Self;

    // Constants
    // @notice Success code for deployment verification
    const DEPLOYMENT_SUCCESS: u64 = 1;

    // @notice Failure code for deployment verification
    const DEPLOYMENT_FAILURE: u64 = 2;

    /// @notice Main function to set up various admin roles in the Aave ACL system
    /// @param account The signer account deploying the script (must be @aave_acl)
    /// @param pool_admins Vector of addresses to assign as pool administrators
    /// @param asset_listing_admins Vector of addresses to assign as asset listing administrators
    /// @param risk_admins Vector of addresses to assign as risk administrators
    /// @param fund_admins Vector of addresses to assign as fund administrators
    /// @param emergency_admins Vector of addresses to assign as emergency administrators
    /// @param flash_borrower_admins Vector of addresses to assign as flash borrower administrators
    /// @param emission_admins Vector of addresses to assign as emission administrators
    /// @param admin_controlled_ecosystem_reserve_funds_admins Vector of addresses to assign as ecosystem reserve funds administrators
    /// @param rewards_controller_admins Vector of addresses to assign as rewards controller administrators
    fun main(
        account: &signer,
        pool_admins: vector<address>,
        asset_listing_admins: vector<address>,
        risk_admins: vector<address>,
        fund_admins: vector<address>,
        emergency_admins: vector<address>,
        flash_borrower_admins: vector<address>,
        emission_admins: vector<address>,
        admin_controlled_ecosystem_reserve_funds_admins: vector<address>,
        rewards_controller_admins: vector<address>
    ) {
        // Verify the script is executed by the ACL owner
        assert!(signer::address_of(account) == @aave_acl);

        // Set up pool administrators
        vector::for_each(
            pool_admins,
            |pool_admin| {
                acl_manage::add_pool_admin(account, pool_admin);
                assert!(acl_manage::is_pool_admin(pool_admin), DEPLOYMENT_SUCCESS);
            }
        );

        // Set up asset listing administrators
        vector::for_each(
            asset_listing_admins,
            |asset_listing_admin| {
                acl_manage::add_asset_listing_admin(account, asset_listing_admin);
                assert!(
                    acl_manage::is_asset_listing_admin(asset_listing_admin),
                    DEPLOYMENT_SUCCESS
                );
            }
        );

        // Set up risk administrators
        vector::for_each(
            risk_admins,
            |risk_admin| {
                acl_manage::add_risk_admin(account, risk_admin);
                assert!(acl_manage::is_risk_admin(risk_admin), DEPLOYMENT_SUCCESS);
            }
        );

        // Set up fund administrators
        vector::for_each(
            fund_admins,
            |funds_admin| {
                acl_manage::add_funds_admin(account, funds_admin);
                assert!(acl_manage::is_funds_admin(funds_admin), DEPLOYMENT_SUCCESS);
            }
        );

        // Set up emergency administrators
        vector::for_each(
            emergency_admins,
            |emergency_admin| {
                acl_manage::add_emergency_admin(account, emergency_admin);
                assert!(
                    acl_manage::is_emergency_admin(emergency_admin),
                    DEPLOYMENT_SUCCESS
                );
            }
        );

        // Set up flash borrower administrators
        vector::for_each(
            flash_borrower_admins,
            |flash_borrower_admin| {
                acl_manage::add_flash_borrower(account, flash_borrower_admin);
                assert!(
                    acl_manage::is_flash_borrower(flash_borrower_admin),
                    DEPLOYMENT_SUCCESS
                );
            }
        );

        // Set up emission administrators
        vector::for_each(
            emission_admins,
            |emission_admin| {
                acl_manage::add_emission_admin(account, emission_admin);
                assert!(
                    acl_manage::is_emission_admin(emission_admin), DEPLOYMENT_SUCCESS
                );
            }
        );

        // Set up ecosystem reserve funds administrators
        vector::for_each(
            admin_controlled_ecosystem_reserve_funds_admins,
            |ecosystem_reserve_funds_admin| {
                acl_manage::add_admin_controlled_ecosystem_reserve_funds_admin(
                    account, ecosystem_reserve_funds_admin
                );
                assert!(
                    acl_manage::is_admin_controlled_ecosystem_reserve_funds_admin(
                        ecosystem_reserve_funds_admin
                    ),
                    DEPLOYMENT_SUCCESS
                );
            }
        );

        // Set up rewards controller administrators
        vector::for_each(
            rewards_controller_admins,
            |rewards_controller_admin| {
                acl_manage::add_rewards_controller_admin(
                    account, rewards_controller_admin
                );
                assert!(
                    acl_manage::is_rewards_controller_admin(rewards_controller_admin),
                    DEPLOYMENT_SUCCESS
                );
            }
        );
    }
}
