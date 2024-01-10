use starknet::{ContractAddress, ClassHash};
#[starknet::interface]
trait IInscriptions<TContractState> {


    //admin function
    fn update_fee(ref self: TContractState, mint_fee:u128, deploy_fee:u128);
    fn update_fund_addr(ref self: TContractState, new_fund:ContractAddress);


    fn inscribe(ref self: TContractState, tick: felt252, amt: u128, t: felt252);

    fn inscribe_data(ref self: TContractState, data:Array<felt252>, t:felt252);

    fn transfer_data(
        ref self: TContractState, to: ContractAddress, inscriptions_id:u128
    );

    fn transfer_data_from(
        ref self: TContractState, from:ContractAddress ,to: ContractAddress, inscriptions_id:u128
    );


    // fn approve(
    //         ref self: TContractState, spender: ContractAddress, tick:felt252 , amt: u128
    //     ) -> bool;

    fn deploy(ref self: TContractState, tick: felt252, max: u128, lim: u128, t: felt252);

    fn transfer(
        ref self: TContractState, to: ContractAddress, tick: felt252, amt: u128, t: felt252
    ) -> u128;

    fn transfer_from(
        ref self: TContractState, from:ContractAddress ,to: ContractAddress, tick: felt252, amt: u128, t: felt252
    ) -> u128;

    fn upgrage(ref self: TContractState, _new_class_hash: ClassHash);

    fn set_market_address(ref self: TContractState, market_address:ContractAddress);

    fn get_user_balance(
        self: @TContractState, tick: felt252, user_address: ContractAddress
    ) -> u128;
}

#[starknet::interface]
trait IERC20<TState> {
    fn name(self: @TState) -> felt252;
    fn symbol(self: @TState) -> felt252;
    fn decimals(self: @TState) -> u8;
    fn total_supply(self: @TState) -> u256;
    fn balance_of(self: @TState, account: ContractAddress) -> u256;
    fn allowance(self: @TState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn transfer(ref self: TState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(
        ref self: TState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
    fn approve(ref self: TState, spender: ContractAddress, amount: u256) -> bool;

    // for eth starknet
    fn transferFrom(
        ref self: TState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
}



#[starknet::contract]
mod Inscriptions {
    use insctiptions::inscriptions::IInscriptions;
use core::starknet::SyscallResultTrait;
    use core::traits::Into;
    use integer::BoundedInt;
    use core::starknet::event::EventEmitter;
    use starknet::{
        ContractAddress, get_caller_address, ClassHash, contract_address_try_from_felt252,
        replace_class_syscall
    };
    use super::{IInscriptionsDispatcher, IInscriptionsDispatcherTrait, IERC20Dispatcher, IERC20DispatcherTrait};


    #[storage]
    struct Storage {
        current_id: u128,
        mint_fee:u128,
        deploy_fee:u128,
        admin: ContractAddress,
        fund_addr:ContractAddress,
        market_address:ContractAddress,
        owner: LegacyMap<(ContractAddress, felt252), u128>,
        owner_data:LegacyMap<u128,ContractAddress>,
        balance: LegacyMap<(ContractAddress, felt252), u128>,
        token_info: LegacyMap<felt252, TokenInfo>,
        user_minted: LegacyMap<(ContractAddress, felt252), u128>,
        // allowances: LegacyMap<(ContractAddress, ContractAddress,felt252), u128>
    }

    #[constructor]
    fn constructor(ref self: ContractState, _admin: felt252, fund_addr:ContractAddress ,mint_fee:u128, deploy_fee:u128) {
        let admin_addr = contract_address_try_from_felt252(_admin).unwrap();
        self.admin.write(admin_addr);
        self.fund_addr.write(fund_addr);
        self.mint_fee.write(mint_fee);
        self.deploy_fee.write(deploy_fee);
    }

    #[derive(Copy, Drop, Serde, starknet::Store)]
    struct TokenInfo {
        tick: felt252,
        max: u128,
        lim: u128,
        total_minted: u128
    }


    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        InscriptionsEvent: InscriptionsEvent,
        InscriptionsDataEvent:InscriptionsDataEvent,
        DeployInscriptionsEvent: DeployInscriptionsEvent,
        TransferInscriptionsEvent:TransferInscriptionsEvent,
        TransferInscriptionsDataEvent:TransferInscriptionsDataEvent,
        ApprovalEvent:ApprovalEvent,
        Upgraded: Upgraded
    }

    #[derive(Drop, starknet::Event)]
    struct Upgraded {
        implementation: ClassHash
    }

    #[derive(Drop, starknet::Event)]
    struct InscriptionsDataEvent {
        #[key]
        inscriptions_id: u128,
        to:ContractAddress,
        inscriptions_data:Array<felt252>,
        t: felt252
    }

    #[derive(Drop, starknet::Event)]
    struct InscriptionsEvent {
        #[key]
        op: felt252,
        #[key]
        tick: felt252,
        p: felt252,
        to: ContractAddress,
        amt: u128,
        inscriptions_id: u128,
        t: felt252
    }

    #[derive(Drop, starknet::Event)]
    struct DeployInscriptionsEvent {
        #[key]
        op: felt252,
        #[key]
        tick: felt252,
        p: felt252,
        lim: u128,
        max: u128,
        to: ContractAddress,
        inscriptions_id: u128,
        t: felt252
    }

    #[derive(Drop, starknet::Event)]
    struct TransferInscriptionsEvent {
        #[key]
        op: felt252,
        #[key]
        tick: felt252,
        p: felt252,
        from: ContractAddress,
        to: ContractAddress,
        amt: u128,
        inscriptions_id: u128,
        t: felt252
    }

     #[derive(Drop, starknet::Event)]
    struct TransferInscriptionsDataEvent {
        #[key]
        inscriptions_id: u128,
        from:ContractAddress,
        to:ContractAddress
    }

 #[derive(Drop, starknet::Event)]
    struct ApprovalEvent {
        owner:ContractAddress,
        spender:ContractAddress,
        tick:felt252,
        amount:u128
    }

    #[external(v0)]
    impl ImplInscriptions of super::IInscriptions<ContractState> {

        fn update_fee(ref self: ContractState, mint_fee:u128, deploy_fee:u128){
            let caller = get_caller_address();
            assert(caller == self.admin.read(), 'Invalid Admin');
            self.mint_fee.write(mint_fee);
            self.deploy_fee.write(deploy_fee);
        }
        fn update_fund_addr(ref self: ContractState, new_fund:ContractAddress){
            let caller = get_caller_address();
            assert(caller == self.admin.read(), 'Invalid Admin');
            self.fund_addr.write(new_fund);
        }

        fn set_market_address(ref self: ContractState, market_address:ContractAddress){
            let caller = get_caller_address();
            assert(caller == self.admin.read(), 'Invalid Admin');
            self.market_address.write(market_address);
        }

        fn inscribe(ref self: ContractState, tick: felt252, amt: u128, t: felt252) {
            let inscriptions_id = self.current_id.read() + 1;
            self.current_id.write(inscriptions_id);
            let token_info = self.token_info.read(tick);
            assert(token_info.tick == tick, 'tick not found');
            assert(token_info.total_minted + amt <= token_info.max, 'minted full');
            let caller = get_caller_address();
            let user_minted = self.user_minted.read((caller, tick));
            assert(user_minted + amt <= token_info.lim, 'max limit');


            let eth_contract: ContractAddress = contract_address_try_from_felt252(0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7).unwrap();
            IERC20Dispatcher {contract_address: eth_contract}.transferFrom(caller, self.fund_addr.read(), self.mint_fee.read().into());

            // update user_minted
            self.user_minted.write((caller, tick), user_minted + amt);
            self.owner.write((caller, tick), inscriptions_id);
            let current_balance = self.balance.read((caller, tick));
            self.balance.write((caller, tick), current_balance + amt);

            //update tokenInfo
            let new_token_info = TokenInfo {
                tick: token_info.tick,
                max: token_info.max,
                lim: token_info.lim,
                total_minted: token_info.total_minted + amt
            };

            self.token_info.write(tick, new_token_info);

            self
                .emit(
                    InscriptionsEvent {
                        p: 'strk-20', op: 'mint', to: caller, tick, amt, inscriptions_id, t
                    }
                )
        }

        fn inscribe_data(ref self: ContractState, data:Array<felt252>, t:felt252){
            let inscriptions_id = self.current_id.read() + 1;
            self.current_id.write(inscriptions_id);
            let caller = get_caller_address();
            self.owner_data.write(inscriptions_id,caller);

             let eth_contract: ContractAddress = contract_address_try_from_felt252(0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7).unwrap();
            IERC20Dispatcher {contract_address: eth_contract}.transferFrom(caller, self.fund_addr.read(), self.mint_fee.read().into());

            self
                .emit(
                    InscriptionsDataEvent {
                        inscriptions_id , inscriptions_data:data ,t, to:caller
                    }
                )
        }

        fn transfer_data(
        ref self: ContractState, to: ContractAddress, inscriptions_id:u128
    ){
        let caller = get_caller_address();
        assert(caller == self.owner_data.read(inscriptions_id), 'Not owner');
        self.owner_data.write(inscriptions_id,to);
        self
                .emit(
                    TransferInscriptionsDataEvent {
                        inscriptions_id,
                        from:caller,
                        to
                    }
                )
    }

    fn transfer_data_from(
        ref self: ContractState, from:ContractAddress ,to: ContractAddress, inscriptions_id:u128
    ){
        let caller = get_caller_address();
        assert(self.market_address.read() == caller, 'Invalid');

        assert(from == self.owner_data.read(inscriptions_id), 'Not owner');
        self.owner_data.write(inscriptions_id,to);
        self
                .emit(
                    TransferInscriptionsDataEvent {
                        inscriptions_id,
                        from,
                        to
                    }
                )
    }

        // fn approve(
        //     ref self: ContractState, spender: ContractAddress, tick:felt252 , amt: u128
        // ) -> bool {
        //     let caller = get_caller_address();
        //     self._approve(caller,spender,tick,amt);
        //     true
        // }

        fn deploy(ref self: ContractState, tick: felt252, max: u128, lim: u128, t: felt252) {
            let inscriptions_id = self.current_id.read() + 1;
            self.current_id.write(inscriptions_id);
            let token_info = self.token_info.read(tick);
            assert(token_info.tick != tick, 'tick existed');
            let caller = get_caller_address();

            self.owner.write((caller, tick), inscriptions_id);

            let eth_contract: ContractAddress = contract_address_try_from_felt252(0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7).unwrap();
            IERC20Dispatcher {contract_address: eth_contract}.transferFrom(caller, self.fund_addr.read(), self.deploy_fee.read().into());

            let new_token_info = TokenInfo { tick, max, lim, total_minted: 0 };
            self.token_info.write(tick, new_token_info);

            self
                .emit(
                    DeployInscriptionsEvent {
                        op: 'deploy', tick, p: 'strk-20', lim, max, to: caller, inscriptions_id, t
                    }
                )
        }

        fn transfer(
            ref self: ContractState, to: ContractAddress, tick: felt252, amt: u128, t: felt252
        ) -> u128 {
            let inscriptions_id = self.current_id.read() + 1;
            self.current_id.write(inscriptions_id);
            let token_info = self.token_info.read(tick);
            assert(token_info.tick == tick, 'tick not found');
            let caller = get_caller_address();

            let current_balance = self.balance.read((caller, tick));
            self.balance.write((caller, tick), current_balance - amt);

            let to_balance = self.balance.read((to, tick));
            self.balance.write((to, tick), to_balance + amt);

            self.owner.write((to, tick), inscriptions_id);

            self
                .emit(
                    TransferInscriptionsEvent {
                        p: 'strk-20',
                        op: 'transfer',
                        from: caller,
                        to,
                        tick,
                        amt,
                        inscriptions_id,
                        t
                    }
                );

                inscriptions_id
        }

        fn transfer_from(
        ref self: ContractState, from:ContractAddress ,to: ContractAddress, tick: felt252, amt: u128, t: felt252
    ) -> u128{
            let caller = get_caller_address();
            // self._spend_allowance(from, caller, tick, amt);
            assert(self.market_address.read() == caller, 'Invalid');

            let inscriptions_id = self.current_id.read() + 1;
            self.current_id.write(inscriptions_id);
            let token_info = self.token_info.read(tick);
            assert(token_info.tick == tick, 'tick not found');
            
            let current_balance = self.balance.read((from, tick));
            self.balance.write((from, tick), current_balance - amt);

            let to_balance = self.balance.read((to, tick));
            self.balance.write((to, tick), to_balance + amt);

            self.owner.write((to, tick), inscriptions_id);

            self
                .emit(
                    TransferInscriptionsEvent {
                        p: 'strk-20',
                        op: 'transfer',
                        from,
                        to,
                        tick,
                        amt,
                        inscriptions_id,
                        t
                    }
                );

                inscriptions_id

    }

        fn upgrage(ref self: ContractState, _new_class_hash: ClassHash) {
            let caller = get_caller_address();
            let admin_addr = self.admin.read();
            assert(caller == admin_addr, 'Invalid Admin');


            assert(!_new_class_hash.is_zero(), 'Class hash cannot be zero');
            replace_class_syscall(_new_class_hash).unwrap_syscall();
            self.emit(Event::Upgraded(Upgraded { implementation: _new_class_hash }))
        }

        fn get_user_balance(
            self: @ContractState, tick: felt252, user_address: ContractAddress
        ) -> u128 {
            let current_balance = self.balance.read((user_address, tick));
            current_balance
        }
    }

    // #[generate_trait]
    // impl Private of PrivateTrait {

    // fn _approve(
    //         ref self: ContractState,
    //         owner: ContractAddress,
    //         spender: ContractAddress,
    //         tick:felt252,
    //         amount: u128
    //     ) {
    //         assert(!owner.is_zero(), 'APPROVE_FROM_ZERO');
    //         assert(!spender.is_zero(),'APPROVE_TO_ZERO');
    //         self.allowances.write((owner, spender,tick), amount);
    //         self.emit(ApprovalEvent { owner, spender, amount, tick });
    //     }

    //  fn _spend_allowance(
    //         ref self:ContractState,
    //         owner: ContractAddress,
    //         spender: ContractAddress,
    //         tick:felt252,
    //         amount: u128
    //     ) {
    //         let current_allowance = self.allowances.read((owner, spender,tick));
    //         if current_allowance != BoundedInt::max() {
    //             self._approve(owner, spender, tick,current_allowance - amount);
    //         }
    //     }   
    // }
}
