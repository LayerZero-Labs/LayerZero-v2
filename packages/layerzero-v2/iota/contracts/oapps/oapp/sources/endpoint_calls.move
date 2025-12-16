module oapp::endpoint_calls;

use call::call::{Call, Void};
use endpoint_v2::{
    endpoint_v2::EndpointV2,
    message_lib_set_config::SetConfigParam as MessageLibSetConfigParam,
    messaging_channel::MessagingChannel
};
use oapp::oapp::{AdminCap, OApp};
use iota::clock::Clock;
use utils::bytes32::Bytes32;

// === Endpoint Functions ===

/// Registers an OApp with the LayerZero V2 endpoint, creating its messaging channel.
///
/// This function creates the essential infrastructure for an OApp to participate in cross-chain
/// messaging by:
/// 1. Creating a specific MessagingChannel shared object for isolated message state
/// 2. Registering the OApp in the registry with its metadata
/// 3. Establishing the mapping between OApp address and its messaging channel
///
/// **Parameters**:
/// - `oapp`: The OApp object instance
/// - `admin`: Admin capability for authorization
/// - `endpoint`: The LayerZero V2 endpoint to register with
/// - `oapp_info`: Execution metadata for OApp related operations, e.g. admin_cap, oapp object address, lz_receive
/// calls, etc.
///
/// **Returns**: The address of the created messaging channel
public fun register_oapp(
    oapp: &OApp,
    admin: &AdminCap,
    endpoint: &mut EndpointV2,
    oapp_info: vector<u8>,
    ctx: &mut TxContext,
): address {
    oapp.assert_admin(admin);
    endpoint.register_oapp(oapp.oapp_cap(), oapp_info, ctx)
}

/// Sets the delegate address for the OApp.
///
/// This function allows OApps to set a delegate address that will be used to authorize
/// certain operations on the OApp.
///
/// **Parameters**:
/// - `oapp`: The OApp object instance
/// - `admin`: Admin capability for authorization
/// - `endpoint`: The LayerZero V2 endpoint
/// - `new_delegate`: The delegate address to set
public fun set_delegate(oapp: &OApp, admin: &AdminCap, endpoint: &mut EndpointV2, new_delegate: address) {
    oapp.assert_admin(admin);
    endpoint.set_delegate(oapp.oapp_cap(), new_delegate);
}

/// Updates the OApp related information for the OApp.
///
/// This function allows OApps to update their OApp related information that
/// the executor uses for message delivery.
///
/// **Parameters**:
/// - `oapp`: The OApp object instance
/// - `admin`: Admin capability for authorization
/// - `endpoint`: The LayerZero V2 endpoint
/// - `oapp_info`: New OApp related information for the OApp
public fun set_oapp_info(oapp: &OApp, admin: &AdminCap, endpoint: &mut EndpointV2, oapp_info: vector<u8>) {
    oapp.assert_admin(admin);
    endpoint.set_oapp_info(oapp.oapp_cap(), oapp.oapp_cap_id(), oapp_info);
}

/// Initializes a new channel path for communication between this OApp and a remote OApp.
///
/// Channel initialization establishes the communication pathway and initializes nonce tracking
/// for message sequencing. This must be called before any messages can be sent or received
/// on this specific path.
///
/// **Parameters**:
/// - `oapp`: The OApp object instance
/// - `admin`: Admin capability for authorization
/// - `endpoint`: The LayerZero V2 endpoint
/// - `messaging_channel`: The OApp's messaging channel
/// - `remote_eid`: The endpoint ID of the remote chain
/// - `remote_oapp`: The bytes32 address of the remote OApp to communicate with
public fun init_channel(
    oapp: &OApp,
    admin: &AdminCap,
    endpoint: &EndpointV2,
    messaging_channel: &mut MessagingChannel,
    remote_eid: u32,
    remote_oapp: Bytes32,
    ctx: &mut TxContext,
) {
    oapp.assert_admin(admin);
    endpoint.init_channel(oapp.oapp_cap(), messaging_channel, remote_eid, remote_oapp, ctx);
}

/// Clears a verified message payload from the messaging channel.
///
/// The OApp can remove the verified payload hash from storage in PULL mode.
///
/// **Parameters**:
/// - `oapp`: The OApp object instance
/// - `admin`: Admin capability for authorization
/// - `endpoint`: The LayerZero V2 endpoint
/// - `messaging_channel`: The OApp's messaging channel
/// - `src_eid`: Source endpoint ID
/// - `sender`: Remote OApp address that sent the message
/// - `nonce`: Message sequence number
/// - `guid`: Global unique identifier for the message
/// - `message`: The actual message payload
public fun clear(
    oapp: &OApp,
    admin: &AdminCap,
    endpoint: &EndpointV2,
    messaging_channel: &mut MessagingChannel,
    src_eid: u32,
    sender: Bytes32,
    nonce: u64,
    guid: Bytes32,
    message: vector<u8>,
) {
    oapp.assert_admin(admin);
    endpoint.clear(
        oapp.oapp_cap(),
        messaging_channel,
        src_eid,
        sender,
        nonce,
        guid,
        message,
    );
}

/// Skips verification of the message at the next inbound nonce.
///
/// This function allows OApps to skip problematic messages that may be causing
/// delivery issues.
///
/// **Security**:
/// - Only the receiving OApp can skip its own messages
/// - Requires exact nonce to prevent skipping the unintended nonce
///
/// **Parameters**:
/// - `oapp`: The OApp object instance
/// - `admin`: Admin capability for authorization
/// - `endpoint`: The LayerZero V2 endpoint
/// - `messaging_channel`: The OApp's messaging channel
/// - `src_eid`: Source endpoint ID
/// - `sender`: Remote OApp address
/// - `nonce`: Exact nonce to skip (prevents unintended skips)
public fun skip(
    oapp: &OApp,
    admin: &AdminCap,
    endpoint: &EndpointV2,
    messaging_channel: &mut MessagingChannel,
    src_eid: u32,
    sender: Bytes32,
    nonce: u64,
) {
    oapp.assert_admin(admin);
    endpoint.skip(
        oapp.oapp_cap(),
        messaging_channel,
        src_eid,
        sender,
        nonce,
    );
}

/// Nilifies a message, maintaining verification status but preventing delivery.
///
/// This function keeps a message's verification status but prevents its execution
/// until it's verified again. Used for messages that may have security concerns
/// but shouldn't be permanently skipped.
///
/// **Parameters**:
/// - `oapp`: The OApp object instance
/// - `admin`: Admin capability for authorization
/// - `endpoint`: The LayerZero V2 endpoint
/// - `messaging_channel`: The OApp's messaging channel
/// - `src_eid`: Source endpoint ID
/// - `sender`: Remote OApp address
/// - `nonce`: Message sequence number
/// - `payload_hash`: Hash of the message payload
public fun nilify(
    oapp: &OApp,
    admin: &AdminCap,
    endpoint: &EndpointV2,
    messaging_channel: &mut MessagingChannel,
    src_eid: u32,
    sender: Bytes32,
    nonce: u64,
    payload_hash: Bytes32,
) {
    oapp.assert_admin(admin);
    endpoint.nilify(
        oapp.oapp_cap(),
        messaging_channel,
        src_eid,
        sender,
        nonce,
        payload_hash,
    );
}

/// Permanently marks a nonce as unexecutable and un-verifiable.
///
/// This function provides the most extreme form of message handling by permanently
/// blocking a specific nonce from any future verification or execution. Used only
/// in severe security situations where a message must never be processed.
///
/// **Warning**: This action is irreversible and blocks the nonce permanently
///
/// **Parameters**:
/// - `oapp`: The OApp object instance
/// - `admin`: Admin capability for authorization
/// - `endpoint`: The LayerZero V2 endpoint
/// - `messaging_channel`: The OApp's messaging channel
/// - `src_eid`: Source endpoint ID
/// - `sender`: Remote OApp address
/// - `nonce`: Message sequence number to permanently block
/// - `payload_hash`: Hash of the message payload
public fun burn(
    oapp: &OApp,
    admin: &AdminCap,
    endpoint: &EndpointV2,
    messaging_channel: &mut MessagingChannel,
    src_eid: u32,
    sender: Bytes32,
    nonce: u64,
    payload_hash: Bytes32,
) {
    oapp.assert_admin(admin);
    endpoint.burn(
        oapp.oapp_cap(),
        messaging_channel,
        src_eid,
        sender,
        nonce,
        payload_hash,
    );
}

/// Sets the send library for a specific destination endpoint.
///
/// Allows OApps to choose their preferred send library for different destination chains.
/// This enables OApps to optimize for different trade-offs based on the destination and
/// use case requirements.
///
/// If the OApp has not set a send library for a specific destination endpoint,
/// the endpoint will use the default send library for that destination.
///
/// **Parameters**:
/// - `oapp`: The OApp object instance
/// - `admin`: Admin capability for authorization
/// - `endpoint`: The LayerZero V2 endpoint
/// - `dst_eid`: The destination endpoint ID to configure the library for
/// - `new_lib`: The send library address to use
public fun set_send_library(oapp: &OApp, admin: &AdminCap, endpoint: &mut EndpointV2, dst_eid: u32, new_lib: address) {
    oapp.assert_admin(admin);
    endpoint.set_send_library(oapp.oapp_cap(), oapp.oapp_cap_id(), dst_eid, new_lib);
}

/// Sets the receive library for a specific source endpoint with a grace period.
///
/// Configures which library will verify inbound messages from a specific source chain.
/// The grace period allows for safe library transitions without disrupting in-flight messages.
///
/// If the OApp has not set a receive library for a specific source endpoint,
/// the endpoint will use the default receive library for that source.
///
/// **Note**: Using seconds instead of block numbers for timeout calculations because
/// IOTA does not have block numbers.
///
/// **Parameters**:
/// - `oapp`: The OApp object instance
/// - `admin`: Admin capability for authorization
/// - `endpoint`: The LayerZero V2 endpoint
/// - `src_eid`: The source endpoint ID to configure the library for
/// - `new_lib`: The receive library address to use
/// - `grace_period`: Transition period in seconds for previous library to verify messages
public fun set_receive_library(
    oapp: &OApp,
    admin: &AdminCap,
    endpoint: &mut EndpointV2,
    src_eid: u32,
    new_lib: address,
    grace_period: u64,
    clock: &Clock,
) {
    oapp.assert_admin(admin);
    endpoint.set_receive_library(
        oapp.oapp_cap(),
        oapp.oapp_cap_id(),
        src_eid,
        new_lib,
        grace_period,
        clock,
    );
}

/// Sets a custom timeout for a specific receive library configuration.
///
/// Allows OApps to override the grace period for a specific library transition.
/// This provides fine-grained control over library switching timelines.
///
/// **Parameters**:
/// - `oapp`: The OApp object instance
/// - `admin`: Admin capability for authorization
/// - `endpoint`: The LayerZero V2 endpoint
/// - `src_eid`: The source endpoint ID
/// - `lib`: The receive library address
/// - `expiry`: Custom expiry timestamp in seconds for the library timeout
public fun set_receive_library_timeout(
    oapp: &OApp,
    admin: &AdminCap,
    endpoint: &mut EndpointV2,
    src_eid: u32,
    lib: address,
    expiry: u64,
    clock: &Clock,
) {
    oapp.assert_admin(admin);
    endpoint.set_receive_library_timeout(
        oapp.oapp_cap(),
        oapp.oapp_cap_id(),
        src_eid,
        lib,
        expiry,
        clock,
    );
}

/// Initiates the configuration flow for updating message library settings.
///
/// **Configuration Flow Process**:
/// 1. **set_config()** - OApp requests a configuration update from the endpoint (this function)
/// 2. **message library processes** - Message library processes the configuration and destroys the call
///
/// This function begins the configuration process by validating the target message library
/// is registered, then creating a call to the library for configuration processing.
///
/// **Parameters**:
/// - `oapp`: The OApp object instance
/// - `admin`: Admin capability for authorization
/// - `endpoint`: The LayerZero V2 endpoint
/// - `lib`: The target message library address to configure
/// - `eid`: The endpoint ID
/// - `config_type`: The type of configuration
/// - `config`: The configuration data
///
/// **Returns**: A call to the message library for config processing
public fun set_config(
    oapp: &OApp,
    admin: &AdminCap,
    endpoint: &EndpointV2,
    lib: address,
    eid: u32,
    config_type: u32,
    config: vector<u8>,
    ctx: &mut TxContext,
): Call<MessageLibSetConfigParam, Void> {
    oapp.assert_admin(admin);
    endpoint.set_config(
        oapp.oapp_cap(),
        oapp.oapp_cap_id(),
        lib,
        eid,
        config_type,
        config,
        ctx,
    )
}
