module Jarjar::AIContract {
    use sui::tx_context::TxContext;
    use sui::event::Event;
    use sui::coin::Coin;
    use sui::address::Address;
    use sui::option::{self, Option};
    use sui::vector;
    use sui::balance::Balance;

    struct Submission has key, store {
        id: u64,
        data: vector<u8>,
        result_link: Option<Address>,
        result_data: Option<vector<u8>>,
        owner: Address,
    }

    event SubmissionEvent {
        id: u64,
        data: vector<u8>,
    }

    event RefundEvent {
        id: u64,
        amount: u64,
    }

    struct Registry has key, store {
        submissions: vector<Submission>,
    }

    public fun initialize(ctx: &mut TxContext) {
        let registry = Registry {
            submissions: vector::empty<Submission>(),
        };
        tx_context::create(&registry, ctx);
    }

    public fun new_submission(ctx: &mut TxContext, data: vector<u8>, payment: Coin<Coin<SUI>>, owner: Address) {
        // Ensure payment is received (0.01 SUI)
        assert!(coin::value(&payment) >= 1_000_000, 0); // 1_000_000 microSUI = 0.01 SUI
        coin::burn(payment); // Burn the payment
        
        // Generate a new submission ID
        let id = tx_context::generate_random_number(ctx);
        
        // Create a new submission
        let submission = Submission {
            id,
            data: data,
            result_link: option::none<Address>(),
            result_data: option::none<vector<u8>>(),
            owner,
        };
        
        // Emit event
        event::emit_event(&SubmissionEvent {
            id,
            data,
        });

        // Store the submission in state storage
        let registry = tx_context::borrow_global_mut<Registry>(ctx);
        vector::push_back(&mut registry.submissions, submission);
    }

    public fun store_result(ctx: &mut TxContext, id: u64, link: Address, result_data: vector<u8>, metadata: vector<u8>) {
        let registry = tx_context::borrow_global_mut<Registry>(ctx);

        let index = vector::index_where(&registry.submissions, fun (s: &Submission): bool {
            s.id == id
        });

        match index {
            option::some(i) => {
                let submission = &mut registry.submissions[i];
                submission.result_link = option::some(link);
                submission.result_data = option::some(result_data);

                // Store metadata if needed
                if (!vector::is_empty(&metadata)) {
                    submission.data = metadata;
                }
            },
            option::none => {
                // Handle error: submission not found
                assert!(false, 1); // Error code 1: Submission not found
            }
        }
    }

    public fun delete_submission(ctx: &mut TxContext, id: u64) {
        let registry = tx_context::borrow_global_mut<Registry>(ctx);
        let index = vector::index_where(&registry.submissions, fun (s: &Submission): bool {
            s.id == id
        });

        match index {
            option::some(i) => {
                let submission = vector::swap_remove(&mut registry.submissions, i);
                // Refund storage fees
                let refund_amount = tx_context::delete_object(ctx, &submission);
                let owner = submission.owner;
                let refund_coin = Coin::new(refund_amount, owner);

                // Emit refund event
                event::emit_event(&RefundEvent {
                    id,
                    amount: refund_amount,
                });

                tx_context::transfer(refund_coin, owner, ctx);
            },
            option::none => {
                // Handle error: submission not found
                assert!(false, 1); // Error code 1: Submission not found
            }
        }
    }
}
