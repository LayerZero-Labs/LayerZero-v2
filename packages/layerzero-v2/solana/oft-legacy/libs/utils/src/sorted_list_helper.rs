use anchor_lang::prelude::*;

pub trait EID {
    fn eid(&self) -> u32;
}

pub fn insert_or_update_sorted_list_by_eid<T: EID>(
    list: &mut Vec<T>,
    item: T,
    max_len: usize,
) -> Result<()> {
    let result = list.binary_search_by(|c| c.eid().cmp(&item.eid()));
    match result {
        Ok(index) => {
            list[index] = item;
        },
        Err(index) => {
            require!(list.len() < max_len, Error::InvalidSize);
            list.insert(index, item);
        },
    }
    Ok(())
}

pub fn get_from_sorted_list_by_eid<T: EID + Clone>(list: &[T], eid: u32) -> Result<&T> {
    let result = list.binary_search_by(|c| c.eid().cmp(&eid));
    let index = match result {
        Ok(index) => index,
        Err(_) => return Err(Error::NotFound.into()),
    };
    Ok(&list[index])
}

pub fn remove_from_sorted_list_by_eid<T: EID + Clone>(list: &mut Vec<T>, eid: u32) -> Result<()> {
    let result = list.binary_search_by(|c| c.eid().cmp(&eid));
    match result {
        Ok(index) => {
            list.remove(index);
            Ok(())
        },
        Err(_) => return Err(Error::NotFound.into()),
    }
}

#[error_code]
pub enum Error {
    NotFound,
    InvalidSize,
}
