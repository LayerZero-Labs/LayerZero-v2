/// Module for representing function identifiers used in Programmable Transaction Block (PTB) move calls.
/// This module provides a structure to uniquely identify any Move function by its package address,
/// module name, and function name.
module ptb_move_call::function;

use std::ascii::String;

/// Represents a unique identifier for a Move function.
/// Contains all necessary information to locate and call a specific function.
public struct Function has copy, drop, store {
    // The address of the package containing the function
    package: address,
    // The name of the module within the package
    module_name: String,
    // The name of the function within the module
    function_name: String,
}

/// Creates a new Function identifier.
public fun create(package: address, module_name: String, function_name: String): Function {
    Function { package, module_name, function_name }
}

/// Returns the package address of the function.
public fun package(self: &Function): address {
    self.package
}

/// Returns the module name of the function.
public fun module_name(self: &Function): &String {
    &self.module_name
}

/// Returns the function name.
public fun function_name(self: &Function): &String {
    &self.function_name
}
