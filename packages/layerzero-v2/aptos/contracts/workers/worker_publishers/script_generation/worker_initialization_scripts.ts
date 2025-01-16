/**
 * Initialize DVN script
 * This creates a script that can be used to initialize a DVN that was created using deployer::object_code_deployment.
 * The output is in hex and must be converted to a byte array.
 *
 * The address inputs must be provided in hex with no 0x prefix.
 *
 * Interface:
 * fun initialize_dvn(
 *     publisher: &signer,
 *     dvn_address: address,
 *     deposit_address: address,
 *     admins_concatenated: vector<u8>,  // 32 bytes each
 *     dvn_signers_concatenated: vector<u8>,  // 64 bytes each
 *     quorum: u64,
 *     supported_msglibs_concatenated: vector<u8>, // 32 bytes each
 *     fee_lib: address,
 * )
 *
 * @param stdAddressHex the address of the standard library in hex (without the 0x prefix)
 * @param deployerAddressHex the address of the deployer in hex (without the 0x prefix)
 * @param dvnAddressHex the address of the DVN in hex (without the 0x prefix)
 * @param uln302AddressHex the address of the ULN302 in hex (without the 0x prefix)
 */
const initialize_dvn_script_hex = (
    stdAddressHex: string,
    deployerAddressHex: string,
    dvnAddressHex: string,
    uln302AddressHex: string,
) => (
    `a11ceb0b060000000701000a030a1a042402052657077d9201088f028001068f031d00000001010202030304040503040001` +
    `0606070101000708090002080a020003090b0200010508060c05050a020a02030a0205170c0101010303030a020a05060c0a` +
    `020a0a020303030303030303030a020a050002060c05010c010203060a09000303010a0900010a02010507060c050a050a0a` +
    `02030a050502060c010866726f6d5f62637306766563746f720364766e066d73676c6962166f626a6563745f636f64655f64` +
    `65706c6f796d656e74166765745f636f64655f6f626a6563745f7369676e657205736c6963650a746f5f616464726573730a` +
    `696e697469616c697a652c7365745f776f726b65725f636f6e6669675f666f725f6665655f6c69625f726f7574696e675f6f` +
    `70745f696e${stdAddressHex}${dvnAddressHex}${uln302AddressHex}${deployerAddressHex}030820000000000000` +
    `00030840000000000000000a0501000a0a020100000001b0010b000b0111000c080e080c110e0341050c170a170700190600` +
    `0000000000000021041005140b11010601000000000000002707020c100600000000000000000c14090c090b1707001a0c0c` +
    `0a0904250b14060100000000000000160c140527080c090a140a0c23043b0a140700180c1a0e030a1a0b1a07001638000c0f` +
    `0d100b0f11024409051e0e0641050c180a1807001906000000000000000021044505490b1101060100000000000000270702` +
    `0c1e0600000000000000000c15090c0a0b1807001a0c0e0a0a045a0b15060100000000000000160c15055c080c0a0a150a0e` +
    `2304700a150700180c1c0e060a1c0b1c07001638000c1d0d1e0b1d1102440905530e0441050c190a19070119060000000000` +
    `00000021047a057e0b11010601000000000000002707030c130600000000000000000c16090c0b0b1907011a0c0d0a0b048f` +
    `010b16060100000000000000160c16059101080c0b0a160a0d2304a4010a160701180c1b0e040a1b0b1b07011638000c120d` +
    `130b1244080588010a110b020b100b130b050b1e0b0711030b1108110402`
);

/**
 * Initialize executor script
 * This creates a script that can be used to publish an Executor. The output is in hex and must be converted to a byte
 * array.
 *
 * The address inputs must be provided in hex with no 0x prefix.
 *
 * Interface:
 * fun initialize_executor(
 *     publisher: &signer,
 *     executor_address: address,
 *     deposit_address: address,
 *     role_admin: address,
 *     admins_concatenated: vector<u8>,  // 32 bytes each
 *     supported_msglibs_concatenated: vector<u8>,  // 32 bytes each
 *     fee_lib: address,
 * )
 *
 * @param stdAddressHex the address of the standard library in hex (without the 0x prefix)\
 * @param deployerAddressHex the address of the deployer in hex (without the 0x prefix)
 * @param executorAddressHex the address of the executor in hex (without the 0x prefix)
 * @param uln302AddressHex the address of the ULN302 in hex (without the 0x prefix)
 */
const initialize_executor_script_hex = (
    stdAddressHex: string,
    deployerAddressHex: string,
    executorAddressHex: string,
    uln302AddressHex: string,
) => (
    `a11ceb0b060000000701000a030a1a042402052648076e970108850280010685030e00000001010202030304040503040001` +
    `0606070101000708090002080a020003090b0200010507060c0505050a020a0205100c010103030a020a05060c0303030303` +
    `030a020a050002060c05010c010203060a09000303010a0900010a02010506060c05050a050a050502060c010866726f6d5f` +
    `62637306766563746f72086578656375746f72066d73676c6962166f626a6563745f636f64655f6465706c6f796d656e7416` +
    `6765745f636f64655f6f626a6563745f7369676e657205736c6963650a746f5f616464726573730a696e697469616c697a65` +
    `2c7365745f776f726b65725f636f6e6669675f666f725f6665655f6c69625f726f7574696e675f6f70745f696e` +
    `${stdAddressHex}${executorAddressHex}${uln302AddressHex}${deployerAddressHex}030820000000000000000a` +
    `0501000000017b0b000b0111000c070e070c0e0e0441050c110a1107001906000000000000000021041005140b0e01060100` +
    `0000000000002707010c0d0600000000000000000c0f090c080b1107001a0c0a0a0804250b0f060100000000000000160c0f` +
    `0527080c080a0f0a0a23043b0a0f0700180c130e040a130b1307001638000c0c0d0d0b0c11024409051e0e0541050c120a12` +
    `07001906000000000000000021044505490b0e010601000000000000002707010c160600000000000000000c10090c090b12` +
    `07001a0c0b0a09045a0b10060100000000000000160c10055c080c090a100a0b2304700a100700180c140e050a140b140700` +
    `1638000c150d160b151102440905530a0e0b020b030b0d0b160b0611030b0e08110402`
);

function test() {
    const stdAddressHex = '0'.repeat(63) + '1';
    const deployerAddressHex = '9'.repeat(64);
    const dvnAddressHex = '2'.repeat(64);
    const executorAddressHex = '3'.repeat(64);
    const uln302AddressHex = '4'.repeat(64);

    console.log(initialize_dvn_script_hex(stdAddressHex, deployerAddressHex, dvnAddressHex, uln302AddressHex));
    console.log();
    console.log(initialize_executor_script_hex(stdAddressHex, deployerAddressHex, executorAddressHex, uln302AddressHex));
}

test();
