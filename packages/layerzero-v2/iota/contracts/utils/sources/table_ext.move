/// Extended utilities for working with IOTA's Table type.
///
/// This module provides convenient macros for common table operations that are not
/// available in the standard library, such as upsert operations, safe removal,
/// borrowing with defaults, and error handling variants.
module utils::table_ext;

use iota::table::Table;

/// Insert or update a value in the table.
///
/// If the key already exists, updates the existing value.
/// If the key doesn't exist, inserts a new key-value pair.
///
/// Arguments:
/// * `table` - Mutable reference to the table
/// * `key` - The key to insert or update
/// * `value` - The value to set
///
/// Returns:
/// * `true` if the key was newly inserted (didn't exist before)
/// * `false` if the key already existed and was updated
public macro fun upsert<$K: copy + drop + store, $V: store>($table: &mut Table<$K, $V>, $key: $K, $value: $V): bool {
    let table = $table;
    if (table.contains($key)) {
        let current_value = &mut table[$key];
        *current_value = $value;
        false
    } else {
        table.add($key, $value);
        true
    }
}

/// Safely remove a value from the table.
///
/// Unlike the standard `remove` function, this doesn't abort if the key doesn't exist.
/// Instead, it returns an Option indicating whether the removal was successful.
///
/// Arguments:
/// * `table` - Mutable reference to the table
/// * `key` - The key to remove
///
/// Returns:
/// * `Some(value)` if the key existed and was removed
/// * `None` if the key didn't exist
public macro fun try_remove<$K: copy + drop + store, $V: store>($table: &mut Table<$K, $V>, $key: $K): Option<$V> {
    let table = $table;
    if (table.contains($key)) {
        option::some(table.remove($key))
    } else {
        option::none()
    }
}

/// Borrow a value from the table with a fallback default.
///
/// This is useful when you want to read a value but provide a default
/// in case the key doesn't exist, without modifying the table.
///
/// Arguments:
/// * `table` - Immutable reference to the table
/// * `key` - The key to look up
/// * `default` - Reference to the default value to return if key doesn't exist
///
/// Returns:
/// * Reference to the value if the key exists
/// * Reference to the default value if the key doesn't exist
public macro fun borrow_with_default<$K: copy + drop + store, $V: store>(
    $table: &Table<$K, $V>,
    $key: $K,
    $default: &$V,
): &$V {
    let table = $table;
    if (table.contains($key)) {
        &table[$key]
    } else {
        $default
    }
}

/// Borrow a mutable value from the table, creating it with a default if it doesn't exist.
///
/// This is the "get or create" pattern - if the key exists, returns a mutable reference
/// to the existing value. If it doesn't exist, inserts the default value and returns
/// a mutable reference to it.
///
/// Arguments:
/// * `table` - Mutable reference to the table
/// * `key` - The key to look up or create
/// * `default` - The default value to insert if the key doesn't exist
///
/// Returns:
/// * Mutable reference to the existing or newly created value
public macro fun borrow_mut_with_default<$K: copy + drop + store, $V: store>(
    $table: &mut Table<$K, $V>,
    $key: $K,
    $default: $V,
): &mut $V {
    let table = $table;
    if (!table.contains($key)) {
        table.add($key, $default);
    };
    &mut table[$key]
}

/// Borrow a value from the table or abort with a custom error code.
///
/// This is useful when you expect a key to exist and want to provide
/// a specific error code if it doesn't, rather than using the default
/// table access error.
///
/// Arguments:
/// * `table` - Immutable reference to the table
/// * `key` - The key to look up
/// * `error` - The error code to abort with if the key doesn't exist
///
/// Returns:
/// * Reference to the value if the key exists
///
/// Aborts:
/// * With the specified error code if the key doesn't exist
public macro fun borrow_or_abort<$K: copy + drop + store, $V: store>(
    $table: &Table<$K, $V>,
    $key: $K,
    $error: u64,
): &$V {
    let table = $table;
    assert!(table.contains($key), $error);
    &table[$key]
}

/// Borrow a mutable value from the table or abort with a custom error code.
///
/// Similar to `borrow_or_abort` but returns a mutable reference for modification.
///
/// Arguments:
/// * `table` - Mutable reference to the table
/// * `key` - The key to look up
/// * `error` - The error code to abort with if the key doesn't exist
///
/// Returns:
/// * Mutable reference to the value if the key exists
///
/// Aborts:
/// * With the specified error code if the key doesn't exist
public macro fun borrow_mut_or_abort<$K: copy + drop + store, $V: store>(
    $table: &mut Table<$K, $V>,
    $key: $K,
    $error: u64,
): &mut $V {
    let table = $table;
    assert!(table.contains($key), $error);
    &mut table[$key]
}
