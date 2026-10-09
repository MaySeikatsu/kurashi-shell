//! libpulse backend (PulseAudio or pipewire-pulse).
//!
//! Threading: libpulse runs its own mainloop thread; every context call is made under
//! `Mainloop::lock`. Replies arrive on that thread and are forwarded through std channels, which
//! the worker waits on *without* holding the lock, so no mainloop signalling (and no `unsafe`)
//! is needed.

use std::sync::mpsc::{self, Receiver};
use std::time::Duration;

use anyhow::{Context as _, Result, anyhow, bail};
use libpulse_binding::callbacks::ListResult;
use libpulse_binding::context::subscribe::InterestMaskSet;
use libpulse_binding::context::{Context, FlagSet, State};
use libpulse_binding::mainloop::threaded::Mainloop;
use libpulse_binding::volume::{ChannelVolumes, Volume};

use crate::{Backend, Device, MAX_VOLUME, Notifier, Snapshot};

const TIMEOUT: Duration = Duration::from_secs(2);

pub struct PulseBackend {
    // Field order = drop order: the context must go before its mainloop.
    ctx: Context,
    ml: Mainloop,
    /// Names for id -> name lookups and the default sink's channel layout for volume writes.
    sinks: Vec<(u32, String)>,
    default_sink: Option<String>,
    default_source: Option<String>,
    sink_channels: u8,
}

impl PulseBackend {
    /// Connects and subscribes to sink/source/server events; fails if no server is reachable.
    pub fn connect(notifier: Notifier) -> Result<Self> {
        let mut ml = Mainloop::new().ok_or_else(|| anyhow!("pulse mainloop"))?;
        let mut ctx = Context::new(&ml, "kurashid").ok_or_else(|| anyhow!("pulse context"))?;
        let (state_tx, state_rx) = mpsc::channel::<()>();
        ml.lock();
        // The state callback only pokes the channel; it also fires on later server loss, which
        // reaches the worker as a change and surfaces as a failed snapshot.
        let n = notifier.clone();
        ctx.set_state_callback(Some(Box::new(move || {
            let _ = state_tx.send(());
            n.notify();
        })));
        let connected = ctx.connect(None, FlagSet::NOFAIL, None);
        let started = ml.start();
        ml.unlock();
        connected.map_err(|e| anyhow!("pulse connect: {e}"))?;
        started.map_err(|e| anyhow!("pulse mainloop start: {e}"))?;

        loop {
            ml.lock();
            let st = ctx.get_state();
            ml.unlock();
            match st {
                State::Ready => break,
                State::Failed | State::Terminated => bail!("pulse server unreachable"),
                _ => {
                    state_rx
                        .recv_timeout(TIMEOUT * 3)
                        .map_err(|_| anyhow!("pulse connect timed out"))?;
                }
            }
        }

        ml.lock();
        let n = notifier;
        ctx.set_subscribe_callback(Some(Box::new(move |_, _, _| n.notify())));
        ctx.subscribe(
            InterestMaskSet::SINK | InterestMaskSet::SOURCE | InterestMaskSet::SERVER,
            |_| {},
        );
        ml.unlock();

        Ok(Self {
            ctx,
            ml,
            sinks: Vec::new(),
            default_sink: None,
            default_source: None,
            sink_channels: 2,
        })
    }

    fn with_lock<T>(&mut self, f: impl FnOnce(&mut Context) -> T) -> T {
        self.ml.lock();
        let out = f(&mut self.ctx);
        self.ml.unlock();
        out
    }

    fn collect<T: Send + 'static>(rx: &Receiver<Option<T>>) -> Result<Vec<T>> {
        let mut out = Vec::new();
        loop {
            match rx.recv_timeout(TIMEOUT).context("pulse reply timed out")? {
                Some(v) => out.push(v),
                None => return Ok(out),
            }
        }
    }
}

impl Drop for PulseBackend {
    fn drop(&mut self) {
        self.ml.lock();
        self.ctx.set_subscribe_callback(None);
        self.ctx.set_state_callback(None);
        self.ctx.disconnect();
        self.ml.unlock();
        self.ml.stop();
    }
}

/// Raw values copied out of the callback (the info structs borrow libpulse memory).
struct Raw {
    dev: Device,
    volume: ChannelVolumes,
    is_monitor: bool,
}

fn linear(v: &ChannelVolumes) -> f64 {
    f64::from(v.avg().0) / f64::from(Volume::NORMAL.0)
}

impl Backend for PulseBackend {
    fn snapshot(&mut self) -> Result<Snapshot> {
        let (srv_tx, srv_rx) = mpsc::channel();
        let (sink_tx, sink_rx) = mpsc::channel::<Option<Raw>>();
        let (src_tx, src_rx) = mpsc::channel::<Option<Raw>>();
        self.with_lock(|ctx| {
            if ctx.get_state() != State::Ready {
                return Err(anyhow!("pulse context not ready"));
            }
            let i = ctx.introspect();
            i.get_server_info(move |s| {
                let _ = srv_tx.send((
                    s.default_sink_name.as_deref().map(str::to_owned),
                    s.default_source_name.as_deref().map(str::to_owned),
                ));
            });
            i.get_sink_info_list(move |r| {
                let item = match r {
                    ListResult::Item(s) => Some(Raw {
                        dev: Device {
                            id: s.index,
                            name: s.name.as_deref().unwrap_or_default().to_owned(),
                            description: s.description.as_deref().unwrap_or_default().to_owned(),
                            volume: linear(&s.volume),
                            muted: s.mute,
                        },
                        volume: s.volume,
                        is_monitor: false,
                    }),
                    _ => None,
                };
                let _ = sink_tx.send(item);
            });
            i.get_source_info_list(move |r| {
                let item = match r {
                    ListResult::Item(s) => Some(Raw {
                        dev: Device {
                            id: s.index,
                            name: s.name.as_deref().unwrap_or_default().to_owned(),
                            description: s.description.as_deref().unwrap_or_default().to_owned(),
                            volume: linear(&s.volume),
                            muted: s.mute,
                        },
                        volume: s.volume,
                        // Monitors mirror sinks; they are never a microphone.
                        is_monitor: s.monitor_of_sink.is_some(),
                    }),
                    _ => None,
                };
                let _ = src_tx.send(item);
            });
            Ok(())
        })?;

        let (dsink, dsource) = srv_rx.recv_timeout(TIMEOUT).context("pulse server info")?;
        let sinks = Self::collect(&sink_rx)?;
        let sources: Vec<Raw> = Self::collect(&src_rx)?
            .into_iter()
            .filter(|r| !r.is_monitor)
            .collect();

        let id_of = |devs: &[Raw], name: &Option<String>| {
            name.as_ref()
                .and_then(|n| devs.iter().find(|r| &r.dev.name == n))
                .map(|r| r.dev.id)
        };
        let default_sink = id_of(&sinks, &dsink);
        let default_source = id_of(&sources, &dsource);

        self.sinks = sinks
            .iter()
            .map(|r| (r.dev.id, r.dev.name.clone()))
            .collect();
        self.default_sink = dsink;
        self.default_source = dsource;
        if let Some(r) = sinks.iter().find(|r| Some(r.dev.id) == default_sink) {
            self.sink_channels = r.volume.len().max(1);
        }
        Ok(Snapshot {
            sinks: sinks.into_iter().map(|r| r.dev).collect(),
            sources: sources.into_iter().map(|r| r.dev).collect(),
            default_sink,
            default_source,
        })
    }

    fn set_volume(&mut self, linear: f64) {
        let Some(name) = self.default_sink.clone() else {
            return;
        };
        let raw = (linear.clamp(0.0, MAX_VOLUME) * f64::from(Volume::NORMAL.0)).round() as u32;
        let mut cv = ChannelVolumes::default();
        cv.set(self.sink_channels, Volume(raw));
        self.with_lock(|ctx| {
            ctx.introspect().set_sink_volume_by_name(&name, &cv, None);
        });
    }

    fn set_muted(&mut self, muted: bool) {
        let Some(name) = self.default_sink.clone() else {
            return;
        };
        self.with_lock(|ctx| {
            ctx.introspect().set_sink_mute_by_name(&name, muted, None);
        });
    }

    fn set_default_sink(&mut self, id: u32) {
        let Some((_, name)) = self.sinks.iter().find(|(i, _)| *i == id).cloned() else {
            return;
        };
        self.with_lock(|ctx| {
            ctx.set_default_sink(&name, |_| {});
        });
    }

    fn set_source_muted(&mut self, muted: bool) {
        let Some(name) = self.default_source.clone() else {
            return;
        };
        self.with_lock(|ctx| {
            ctx.introspect().set_source_mute_by_name(&name, muted, None);
        });
    }
}
