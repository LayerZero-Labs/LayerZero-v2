/// Message library type definitions for endpoint v2.
/// Defines the types of message libraries that can be used for cross-chain messaging.
module endpoint_v2::message_lib_type;

// === Structs ===

/// Enumeration of message library types that define the direction of message flow.
/// Used to specify whether a message library handles sending, receiving, or both operations.
public enum MessageLibType has copy, drop, store {
    // Library handles outbound messages only
    Send,
    // Library handles inbound messages only
    Receive,
    // Library handles both inbound and outbound messages
    SendAndReceive,
}

// === Constructor ===

/// Creates a Send message library type.
public fun send(): MessageLibType {
    MessageLibType::Send
}

/// Creates a Receive message library type.
public fun receive(): MessageLibType {
    MessageLibType::Receive
}

/// Creates a SendAndReceive message library type.
public fun send_and_receive(): MessageLibType {
    MessageLibType::SendAndReceive
}
