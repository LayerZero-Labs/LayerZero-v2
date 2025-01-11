/// This is a fork of the original code from the Move standard library.
/// The original code can be found at aptos_framework::object_code_deployment.
/// This has been modified for the following:
///   1) Accept a seed for the object creation to provide deterministic addresses
///   2) Convenience view function to generate the object address given the publisher address and the object seed.
///   3) Function to generate a signer for the code object to be used in scripts
///   4) Function to destroy the ExtendRef for the code object
///   5) Extract repeated code into a function to assert the owner of the code object
///
/// ===================================================================================================================
///
/// This module allows users to deploy, upgrade and freeze modules deployed to objects on-chain.
/// This enables users to deploy modules to an object with a unique address each time they are published.
/// This modules provides an alternative method to publish code on-chain, where code is deployed to objects rather than accounts.
/// This is encouraged as it abstracts the necessary resources needed for deploying modules,
/// along with the required authorization to upgrade and freeze modules.
///
/// The functionalities of this module are as follows.
///
/// Publishing modules flow:
/// 1. Create a new object with the address derived from the publisher address and the object seed.
/// 2. Publish the module passed in the function via `metadata_serialized` and `code` to the newly created object.
/// 3. Emits 'Publish' event with the address of the newly created object.
/// 4. Create a `ManagingRefs` which stores the extend ref of the newly created object.
/// Note: This is needed to upgrade the code as the signer must be generated to upgrade the existing code in an object.
///
/// Upgrading modules flow:
/// 1. Assert the `code_object` passed in the function is owned by the `publisher`.
/// 2. Assert the `code_object` passed in the function exists in global storage.
/// 2. Retrieve the `ExtendRef` from the `code_object` and generate the signer from this.
/// 3. Upgrade the module with the `metadata_serialized` and `code` passed in the function.
/// 4. Emits 'Upgrade' event with the address of the object with the upgraded code.
/// Note: If the modules were deployed as immutable when calling `publish`, the upgrade will fail.
///
/// Freezing modules flow:
/// 1. Assert the `code_object` passed in the function exists in global storage.
/// 2. Assert the `code_object` passed in the function is owned by the `publisher`.
/// 3. Mark all the modules in the `code_object` as immutable.
/// 4. Emits 'Freeze' event with the address of the object with the frozen code.
/// Note: There is no unfreeze function as this gives no benefit if the user can freeze/unfreeze modules at will.
///       Once modules are marked as immutable, they cannot be made mutable again.
module deployer::object_code_deployment {
    use std::error;
    use std::signer;
    use std::code;
    use std::event;
    use std::object::{Self, address_to_object, ExtendRef, ObjectCore};

    /// Object code deployment feature not supported.
    const EOBJECT_CODE_DEPLOYMENT_NOT_SUPPORTED: u64 = 1;
    /// Not the owner of the `code_object`
    const ENOT_CODE_OBJECT_OWNER: u64 = 2;
    /// `code_object` does not exist.
    const ECODE_OBJECT_DOES_NOT_EXIST: u64 = 3;
    /// Arbitrary signer generation is disabled for the code object.
    const EARBITRARY_SIGNER_DISABLED: u64 = 4;

    const OBJECT_CODE_DEPLOYMENT_DOMAIN_SEPARATOR: vector<u8> = b"aptos_framework::object_code_deployment";

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    /// Internal struct, attached to the object, that holds Refs we need to manage the code deployment (i.e. upgrades).
    struct ManagingRefs has key {
        /// We need to keep the extend ref to be able to generate the signer to upgrade existing code.
        extend_ref: ExtendRef,
        /// This flag controls whether this module can release a signer for the code object.
        arbitrary_signer_enabled: bool,
    }

    #[event]
    /// Event emitted when code is published to an object.
    struct Publish has drop, store {
        object_address: address,
    }

    #[event]
    /// Event emitted when code in an existing object is upgraded.
    struct Upgrade has drop, store {
        object_address: address,
    }

    #[event]
    /// Event emitted when code in an existing object is made immutable.
    struct Freeze has drop, store {
        object_address: address,
    }

    #[event]
    struct DisableArbitrarySigner has drop, store {
        object_address: address,
    }

    #[event]
    struct DestroyRefs has drop, store {
        object_address: address,
    }

    #[view]
    /// Gets the object address given the publisher address and the object seed
    public fun compute_object_address(publisher: address, object_seed: vector<u8>): address {
        object::create_object_address(&publisher, object_seed)
    }

    /// Creates a new object with a unique address derived from the publisher address and the object seed.
    /// Publishes the code passed in the function to the newly created object.
    /// The caller must provide package metadata describing the package via `metadata_serialized` and
    /// the code to be published via `code`. This contains a vector of modules to be deployed on-chain.
    public entry fun publish(
        publisher: &signer,
        object_seed: vector<u8>,
        metadata_serialized: vector<u8>,
        code: vector<vector<u8>>,
    ) {
        let constructor_ref = &object::create_named_object(publisher, object_seed);
        let code_signer = &object::generate_signer(constructor_ref);
        code::publish_package_txn(code_signer, metadata_serialized, code);

        event::emit(Publish { object_address: signer::address_of(code_signer) });

        move_to(code_signer, ManagingRefs {
            extend_ref: object::generate_extend_ref(constructor_ref),
            arbitrary_signer_enabled: true,
        });
    }

    /// Upgrades the existing modules at the `code_object` address with the new modules passed in `code`,
    /// along with the metadata `metadata_serialized`.
    /// Note: If the modules were deployed as immutable when calling `publish`, the upgrade will fail.
    /// Requires the publisher to be the owner of the `code_object`.
    public entry fun upgrade(
        publisher: &signer,
        metadata_serialized: vector<u8>,
        code: vector<vector<u8>>,
        code_object: address,
    ) acquires ManagingRefs {
        assert_owner_and_code_object(signer::address_of(move publisher), code_object);

        let extend_ref = &borrow_global<ManagingRefs>(code_object).extend_ref;
        let code_signer = &object::generate_signer_for_extending(extend_ref);
        code::publish_package_txn(code_signer, metadata_serialized, code);

        event::emit(Upgrade { object_address: signer::address_of(code_signer) });
    }

    /// Get an arbitrary signer for the code object, which can be used in scripts or other transactions.
    public fun get_code_object_signer(
        publisher: &signer,
        code_object: address,
    ): signer acquires ManagingRefs {
        assert_owner_and_code_object(signer::address_of(move publisher), code_object);

        // Check if arbitrary signer generation is enabled for the code object
        assert!(
            borrow_global<ManagingRefs>(code_object).arbitrary_signer_enabled,
            EARBITRARY_SIGNER_DISABLED,
        );

        let extend_ref = &borrow_global<ManagingRefs>(code_object).extend_ref;
        object::generate_signer_for_extending(extend_ref)
    }

    /// Disable the ability to generate arbitrary signers for the code object.
    public entry fun disable_arbitrary_signer(publisher: &signer, code_object: address) acquires ManagingRefs {
        let publisher_address = signer::address_of(move publisher);
        assert_owner_and_code_object(publisher_address, code_object);

        // Permanently disable the ability to generate arbitrary signers for the code object
        borrow_global_mut<ManagingRefs>(code_object).arbitrary_signer_enabled = false;

        event::emit(DisableArbitrarySigner { object_address: code_object });
    }

    /// Make an existing upgradable package immutable. Once this is called, the package cannot be made upgradable again.
    /// Each `code_object` should only have one package, as one package is deployed per object in this module.
    /// Requires the `publisher` to be the owner of the `code_object`.
    public entry fun freeze_code_object(publisher: &signer, code_object: address) {
        code::freeze_code_object(publisher, address_to_object(code_object));

        event::emit(Freeze { object_address: code_object });
    }

    /// This permanently destroys the ability to upgrade or sign on behalf of the code object.
    /// This is effectively equivalent to transferring the code object to a burn object, but is more explicit in
    /// destroying the ExtendRef.
    public entry fun destroy_refs(publisher: &signer, code_object: address) acquires ManagingRefs {
        let publisher_address = signer::address_of(move publisher);
        assert_owner_and_code_object(publisher_address, code_object);

        let ManagingRefs {
            extend_ref: _,
            arbitrary_signer_enabled: _,
        } = move_from<ManagingRefs>(publisher_address);

        event::emit(DestroyRefs { object_address: code_object });
    }

    /// Internal function to assert the owner of the `code_object` and asset that there is a code object at the location
    fun assert_owner_and_code_object(publisher_address: address, code_object: address) {
        assert!(
            object::is_owner(address_to_object<ObjectCore>(code_object), publisher_address),
            error::permission_denied(ENOT_CODE_OBJECT_OWNER),
        );

        let code_object_address = code_object;
        assert!(exists<ManagingRefs>(code_object_address), error::not_found(ECODE_OBJECT_DOES_NOT_EXIST));
    }
}
