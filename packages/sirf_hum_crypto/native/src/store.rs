//! Local persistence abstraction (Prompt 06 Part 3, D-058).
//!
//! The store is dumb: it keeps opaque, already-sealed records by name.
//! Confidentiality and integrity come from `record.rs`; atomicity comes from
//! each `put` replacing a record in one step. Local only: nothing here talks
//! to Firebase, and it never will.

use std::collections::BTreeMap;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

use crate::limits::MAX_RECORD_BYTES;
use crate::{CoreError, CoreResult};

pub trait CryptoStore: Send {
    /// Atomically creates or replaces `name`. After an error the previous
    /// record (if any) is unchanged.
    fn put(&mut self, name: &str, record: &[u8]) -> CoreResult<()>;
    fn get(&self, name: &str) -> CoreResult<Option<Vec<u8>>>;
    fn delete(&mut self, name: &str) -> CoreResult<()>;
    fn exists(&self, name: &str) -> CoreResult<bool>;
    /// Removes every record this store owns.
    fn wipe_all(&mut self) -> CoreResult<()>;
}

/// Record names are fixed identifiers chosen by the core, never user input;
/// validated anyway so no name can escape the store directory.
pub(crate) fn check_name(name: &str) -> CoreResult<()> {
    let ok = !name.is_empty()
        && name.len() <= 64
        && name
            .bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'_');
    if ok {
        Ok(())
    } else {
        Err(CoreError::InvalidInput)
    }
}

/// In-memory store for tests.
#[derive(Default)]
pub struct MemoryStore {
    records: BTreeMap<String, Vec<u8>>,
}

impl CryptoStore for MemoryStore {
    fn put(&mut self, name: &str, record: &[u8]) -> CoreResult<()> {
        check_name(name)?;
        self.records.insert(name.to_owned(), record.to_vec());
        Ok(())
    }
    fn get(&self, name: &str) -> CoreResult<Option<Vec<u8>>> {
        check_name(name)?;
        Ok(self.records.get(name).cloned())
    }
    fn delete(&mut self, name: &str) -> CoreResult<()> {
        check_name(name)?;
        self.records.remove(name);
        Ok(())
    }
    fn exists(&self, name: &str) -> CoreResult<bool> {
        check_name(name)?;
        Ok(self.records.contains_key(name))
    }
    fn wipe_all(&mut self) -> CoreResult<()> {
        self.records.clear();
        Ok(())
    }
}

/// One file per record in an app-private directory. `put` writes a temporary
/// file, fsyncs it, then renames it over the old file (an atomic replace on
/// POSIX and on Windows), then fsyncs the directory on POSIX.
///
/// This gives atomic writes, not key protection: protecting the data is the
/// sealing layer's job, and protecting the sealing key is the platform
/// keystore's (keystore.rs).
pub struct FileStore {
    dir: PathBuf,
}

const RECORD_EXT: &str = "shrec";

impl FileStore {
    pub fn open(dir: &Path) -> CoreResult<Self> {
        fs::create_dir_all(dir).map_err(|_| CoreError::PersistenceFailure)?;
        Ok(Self {
            dir: dir.to_path_buf(),
        })
    }

    fn path(&self, name: &str) -> PathBuf {
        self.dir.join(format!("{name}.{RECORD_EXT}"))
    }
}

impl CryptoStore for FileStore {
    fn put(&mut self, name: &str, record: &[u8]) -> CoreResult<()> {
        check_name(name)?;
        let final_path = self.path(name);
        let tmp_path = self.dir.join(format!(".{name}.{RECORD_EXT}.tmp"));
        let write = || -> std::io::Result<()> {
            let mut f = fs::File::create(&tmp_path)?;
            f.write_all(record)?;
            f.sync_all()?;
            drop(f);
            fs::rename(&tmp_path, &final_path)?;
            #[cfg(unix)]
            fs::File::open(&self.dir)?.sync_all()?;
            Ok(())
        };
        write().map_err(|_| {
            let _ = fs::remove_file(&tmp_path);
            CoreError::PersistenceFailure
        })
    }

    fn get(&self, name: &str) -> CoreResult<Option<Vec<u8>>> {
        check_name(name)?;
        let path = self.path(name);
        match fs::metadata(&path) {
            Ok(m) if m.len() as usize > MAX_RECORD_BYTES => Err(CoreError::StateCorruption),
            Ok(_) => fs::read(&path)
                .map(Some)
                .map_err(|_| CoreError::PersistenceFailure),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
            Err(_) => Err(CoreError::PersistenceFailure),
        }
    }

    fn delete(&mut self, name: &str) -> CoreResult<()> {
        check_name(name)?;
        match fs::remove_file(self.path(name)) {
            Ok(()) => Ok(()),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(_) => Err(CoreError::PersistenceFailure),
        }
    }

    fn exists(&self, name: &str) -> CoreResult<bool> {
        check_name(name)?;
        Ok(self.path(name).exists())
    }

    fn wipe_all(&mut self) -> CoreResult<()> {
        let entries = fs::read_dir(&self.dir).map_err(|_| CoreError::PersistenceFailure)?;
        for entry in entries.flatten() {
            let path = entry.path();
            let is_ours = path
                .file_name()
                .and_then(|n| n.to_str())
                .is_some_and(|n| n.ends_with(RECORD_EXT) || n.ends_with(".tmp"));
            if is_ours {
                fs::remove_file(&path).map_err(|_| CoreError::PersistenceFailure)?;
            }
        }
        Ok(())
    }
}
