//! A Pipe is a file buffer hold in memory.
//! It can, for example, be used to replace stdin/stdout/stderr of a WASI module.

use rustler::{Encoder, ResourceArc, Term};
use std::any::Any;
use std::io::{self, Cursor, Read, Seek, Write};
use std::sync::{Arc, Mutex, RwLock};
use wasi_common::{file::FileType, Error, WasiFile};
use wasmtime_wasi::async_trait;
use wiggle::anyhow::anyhow;

use crate::atoms;

fn capacity_exceeded(capacity: Option<u64>) -> String {
    match capacity {
        Some(capacity) => format!("write beyond capacity of Wasmex.Pipe ({capacity} bytes)"),
        None => "write beyond capacity of Wasmex.Pipe".to_string(),
    }
}

/// For piping stdio. Stores all output / input in a byte-vector.
#[derive(Debug, Default)]
pub struct Pipe {
    buffer: Arc<RwLock<Cursor<Vec<u8>>>>,
    /// Maximum number of bytes the backing buffer may grow to.
    /// `None` — the default — leaves the pipe unbounded.
    capacity: Option<u64>,
}

impl Pipe {
    pub fn new() -> Self {
        Self::default()
    }

    /// A pipe whose backing buffer may not grow beyond `capacity` bytes.
    ///
    /// A write that would exceed the capacity is rejected in full — no
    /// partial write — and traps the guest. This mirrors
    /// `wasmtime_wasi::p2::pipe::MemoryOutputPipe`, which is the WASIp2
    /// equivalent of this type.
    ///
    /// This matters because a `Pipe` is host memory: a guest that writes in a
    /// loop can exhaust the host heap while paying almost nothing for it. Fuel
    /// does not help, because `fd_write` is a host call and costs the guest
    /// O(1) regardless of how many bytes it moves. Trapping — rather than
    /// returning an errno — is what actually stops such a guest: an errno can
    /// be ignored, and a guest that ignores it simply writes again.
    pub fn with_capacity(capacity: u64) -> Self {
        Self {
            buffer: Arc::new(RwLock::new(Cursor::new(Vec::new()))),
            capacity: Some(capacity),
        }
    }

    fn borrow(&self) -> std::sync::RwLockWriteGuard<'_, Cursor<Vec<u8>>> {
        RwLock::write(&self.buffer).unwrap()
    }

    fn size(&self) -> u64 {
        let buffer = &*(self.borrow());
        buffer.get_ref().len() as u64
    }

    /// Whether writing `n` bytes at the cursor's current position stays within
    /// `capacity`.
    ///
    /// Checked against the *resulting buffer length*, not against `n`: the
    /// buffer is a `Cursor`, so a write after a seek overwrites existing bytes
    /// and may not grow the allocation at all. Capacity bounds how much memory
    /// the pipe holds, so overwrites must stay free.
    fn fits(capacity: Option<u64>, buffer: &Cursor<Vec<u8>>, n: u64) -> bool {
        match capacity {
            None => true,
            Some(capacity) => {
                let grown = buffer.position().saturating_add(n);
                let projected = std::cmp::max(buffer.get_ref().len() as u64, grown);
                projected <= capacity
            }
        }
    }
}

impl Clone for Pipe {
    fn clone(&self) -> Self {
        Self {
            buffer: self.buffer.clone(),
            capacity: self.capacity,
        }
    }
}

impl Read for Pipe {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        let buffer = &mut *(self.borrow());
        buffer.read(buf)
    }
}

impl Write for Pipe {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        let capacity = self.capacity;
        let buffer = &mut *(self.borrow());

        if !Self::fits(capacity, buffer, buf.len() as u64) {
            return Err(io::Error::other(capacity_exceeded(capacity)));
        }

        buffer.write(buf)
    }

    fn flush(&mut self) -> io::Result<()> {
        let buffer = &mut *(self.borrow());
        buffer.flush()
    }
}

impl Seek for Pipe {
    fn seek(&mut self, pos: io::SeekFrom) -> io::Result<u64> {
        let buffer = &mut *(self.borrow());
        buffer.seek(pos)
    }
}

#[async_trait]
impl WasiFile for Pipe {
    fn as_any(&self) -> &dyn Any {
        self
    }

    async fn get_filetype(&self) -> Result<FileType, Error> {
        Ok(FileType::Pipe)
    }

    async fn write_vectored<'a>(&self, bufs: &[io::IoSlice<'a>]) -> Result<u64, Error> {
        let capacity = self.capacity;
        let buffer = &mut *(self.borrow());

        // The guest's write path. Trap rather than return an errno: an errno
        // is advisory, and a guest looping on `fd_write` to exhaust host
        // memory is exactly the guest that will ignore one.
        let requested: u64 = bufs.iter().map(|buf| buf.len() as u64).sum();
        if !Self::fits(capacity, buffer, requested) {
            return Err(Error::trap(anyhow!(capacity_exceeded(capacity))));
        }

        buffer
            .write_vectored(bufs)
            .map(|written| written as u64)
            .map_err(wasi_common::Error::from)
    }

    async fn read_vectored<'a>(&self, bufs: &mut [io::IoSliceMut<'a>]) -> Result<u64, Error> {
        let buffer = &mut *(self.borrow());
        buffer
            .read_vectored(bufs)
            .map(|read| read as u64)
            .map_err(wasi_common::Error::from)
    }

    fn isatty(&self) -> bool {
        false
    }
}

pub struct PipeResource {
    pub pipe: Mutex<Pipe>,
}

#[rustler::resource_impl()]
impl rustler::Resource for PipeResource {}

#[rustler::nif(name = "pipe_new")]
pub fn new(capacity: Option<u64>) -> Result<ResourceArc<PipeResource>, rustler::Error> {
    let pipe = match capacity {
        Some(capacity) => Pipe::with_capacity(capacity),
        None => Pipe::new(),
    };
    let pipe_resource = ResourceArc::new(PipeResource {
        pipe: Mutex::new(pipe),
    });

    Ok(pipe_resource)
}

#[rustler::nif(name = "pipe_size")]
pub fn size(pipe_resource: ResourceArc<PipeResource>) -> u64 {
    let pipe: &Pipe = &pipe_resource.pipe.lock().unwrap();
    pipe.size()
}

#[rustler::nif(name = "pipe_seek")]
pub fn seek(
    pipe_resource: ResourceArc<PipeResource>,
    pos: u64,
) -> rustler::NifResult<rustler::Atom> {
    let pipe: &mut Pipe = &mut pipe_resource.pipe.lock().unwrap();

    Seek::seek(pipe, io::SeekFrom::Start(pos))
        .map_err(|err| rustler::Error::Term(Box::new(err.to_string())))
        .map(|_| atoms::ok())
}

#[rustler::nif(name = "pipe_read_binary", schedule = "DirtyCpu")]
pub fn read_binary(pipe_resource: ResourceArc<PipeResource>) -> String {
    let mut pipe = pipe_resource.pipe.lock().unwrap();
    let mut buffer = String::new();

    (*pipe).read_to_string(&mut buffer).unwrap();
    buffer
}

#[rustler::nif(name = "pipe_write_binary", schedule = "DirtyCpu")]
pub fn write_binary(
    env: rustler::Env,
    pipe_resource: ResourceArc<PipeResource>,
    content: String,
) -> Term {
    let mut pipe = pipe_resource.pipe.lock().unwrap();

    match (*pipe).write(content.as_bytes()) {
        Ok(bytes_written) => (atoms::ok(), bytes_written).encode(env),
        _ => atoms::error().encode(env),
    }
}
