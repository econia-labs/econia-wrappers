module econia_wrappers::wrappers {
    use aptos_std::coin;
    use econia::market;
    use econia::user::{
        deposit_from_coinstore,
        get_market_account_id,
        has_market_account_by_market_account_id,
        register_market_account,
        withdraw_to_coinstore,
    };
    use std::signer::{address_of};

    const BID: bool = false;
    const BUY: bool = true;
    const NO_CUSTODIAN: u64 = 0;
    const SHIFT_MARKET_ID: u8 = 64;

    fun before_order_placement<
        BaseType,
        QuoteType
    >(
        user: &signer,
        deposit_amount: u64,
        market_id: u64,
        side: bool,
    ) {
        let user_addr = address_of(user);
        // Create MarketAccount if not exists
        // Least significant 64 bits is 0 because we use NO_CUSTODIAN
        let user_market_account_id = get_market_account_id(
            market_id,
            NO_CUSTODIAN,
        );
        if (!has_market_account_by_market_account_id(
            user_addr,
            user_market_account_id
        )) {
            register_market_account<BaseType, QuoteType>(
                user,
                market_id,
                NO_CUSTODIAN
            );
        };

        // Deposit `deposit_amount` into the MarketAccount
        if (side == BID) {
            deposit_from_coinstore<QuoteType>(
                user,
                market_id,
                NO_CUSTODIAN,
                deposit_amount // size * price * tick_size
            );
            // Register the BaseType if it is not registered
            if (!coin::is_account_registered<BaseType>(user_addr)) {
                coin::register<BaseType>(user);
            };
        } else {
            deposit_from_coinstore<BaseType>(
                user,
                market_id,
                NO_CUSTODIAN,
                deposit_amount // size * lot_size
            );
            // Register the QuoteType if it is not registered
            if (!coin::is_account_registered<QuoteType>(user_addr)) {
                coin::register<QuoteType>(user);
            };
        };
    }

    #[cmd]
    /// Convenience script for `market::place_limit_order_user()`.
    ///
    /// This script will create a user MarketAccount if it does not already
    /// exist and will withdraw from the user's CoinStore to ensure there is
    /// sufficient balance to place the Order.
    public entry fun place_limit_order_user_entry<
        BaseType,
        QuoteType
    >(
        user: &signer,
        deposit_amount: u64,
        market_id: u64,
        integrator: address,
        side: bool,
        size: u64,
        price: u64,
        restriction: u8,
    ) {
        before_order_placement<BaseType, QuoteType>(
            user,
            deposit_amount,
            market_id,
            side,
        );
        // Place the order
        market::place_limit_order_user_entry<BaseType, QuoteType>(
            user,
            market_id,
            integrator,
            side,
            size,
            price,
            restriction
        );
    }

    #[cmd]
    /// Convenience script for `market::place_market_order_user()`.
    ///
    /// This script will create a user MarketAccount if it does not already
    /// exist and will withdraw from the user's CoinStore to ensure there is
    /// sufficient balance to place the Order.
    public entry fun place_market_order_user_entry<
        BaseType,
        QuoteType
    >(
        user: &signer,
        deposit_amount: u64,
        market_id: u64,
        integrator: address,
        direction: bool,
        min_base: u64,
        max_base: u64,
        min_quote: u64,
        max_quote: u64,
        limit_price: u64,
    ) {
        before_order_placement<BaseType, QuoteType>(
            user,
            deposit_amount,
            market_id,
            !direction, // side = !direction
        );
        // Place the order
        let (base_traded, quote_traded, _) =
            market::place_market_order_user<BaseType, QuoteType>(
                user,
                market_id,
                integrator,
                direction,
                min_base,
                max_base,
                min_quote,
                max_quote,
                limit_price,
            );
        if (direction == BUY) {
            // Return the unused quote
            withdraw_to_coinstore<BaseType>(
                user,
                market_id,
                base_traded,
            );
        } else {
            // Return the unused base
            withdraw_to_coinstore<QuoteType>(
                user,
                market_id,
                quote_traded,
            );
        };
    }
}